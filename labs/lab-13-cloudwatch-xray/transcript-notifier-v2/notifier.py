"""usms-transcript-notifier v2 — instrumented (Lab 13).

Triggered by S3 ObjectCreated events under transcripts/ in usms-student-data.
For each transcript object it:
  * checks the object is readable (head_object),
  * derives the faculty from transcripts/<faculty>/...,
  * prints one USMS_NOTIFY JSON line (the metric filter counts these),
  * publishes TranscriptsProcessed{Faculty,Stage=notify} and TranscriptLagSeconds{Stage=notify},
and finally prints one USMS_SUMMARY line carrying the trace id.

Telemetry must never break the business path: metric failures are logged as
USMS_METRIC_ERROR and swallowed.
"""
import datetime
import json
import os
import time
import urllib.parse

import boto3
from botocore.config import Config

BUCKET = os.environ.get("USMS_BUCKET", "usms-student-data")
CHANNEL = os.environ.get("USMS_NOTIFY_CHANNEL", "stdout")
NAMESPACE = os.environ.get("USMS_METRIC_NAMESPACE", "USMS/Application")
FACULTY_DEFAULT = os.environ.get("USMS_FACULTY_DEFAULT", "unknown")

# Short timeouts, one attempt: a slow telemetry call must not stall the function.
_CFG = Config(connect_timeout=2, read_timeout=3, retries={"max_attempts": 1})
_s3 = boto3.client("s3", config=_CFG)
_cw = boto3.client("cloudwatch", config=_CFG)


def trace_id(context):
    """X-Ray Root= id from the Lambda trace header; request id if tracing is off."""
    header = os.environ.get("_X_AMZN_TRACE_ID", "")
    for part in header.split(";"):
        if part.startswith("Root="):
            return part[len("Root="):]
    return getattr(context, "aws_request_id", "no-trace")


def describe(record):
    s3 = record.get("s3", {})
    return {
        "event": record.get("eventName", "unknown"),
        "event_time": record.get("eventTime"),
        "bucket": s3.get("bucket", {}).get("name", BUCKET),
        "key": urllib.parse.unquote_plus(s3.get("object", {}).get("key", "")),
        "bytes": s3.get("object", {}).get("size", 0),
    }


def faculty_of(key):
    """transcripts/<faculty>/... -> faculty. Guarded so a bad path cannot explode metric cardinality."""
    parts = key.split("/")
    if len(parts) >= 3 and parts[0] == "transcripts":
        candidate = parts[1].lower()
        if candidate.isalpha() and len(candidate) <= 20:
            return candidate
    return FACULTY_DEFAULT


def lag_seconds(event_time):
    if not event_time:
        return 0.0
    try:
        t = datetime.datetime.fromisoformat(event_time.replace("Z", "+00:00"))
        return max(0.0, round(time.time() - t.timestamp(), 3))
    except ValueError:
        return 0.0


def publish(faculty, lag):
    """Publish metrics; never raise."""
    try:
        _cw.put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[
                {"MetricName": "TranscriptsProcessed", "Unit": "Count", "Value": 1,
                 "Dimensions": [{"Name": "Faculty", "Value": faculty}, {"Name": "Stage", "Value": "notify"}]},
                {"MetricName": "TranscriptLagSeconds", "Unit": "Seconds", "Value": lag,
                 "Dimensions": [{"Name": "Stage", "Value": "notify"}]},
            ],
        )
        return True
    except Exception as exc:  # telemetry must not fail the invocation
        print("USMS_METRIC_ERROR " + json.dumps({"error": type(exc).__name__, "detail": str(exc)[:200]}))
        return False


def notify(item, tid):
    line = dict(item, trace_id=tid, channel=CHANNEL)
    print("USMS_NOTIFY " + json.dumps(line, sort_keys=True))


def handler(event, context):
    started = time.time()
    tid = trace_id(context)
    processed, skipped = [], 0

    for record in event.get("Records", []):
        item = describe(record)
        if not item["key"].startswith("transcripts/"):
            skipped += 1
            continue
        try:
            _s3.head_object(Bucket=item["bucket"], Key=item["key"])
            item["readable"] = True
        except Exception:
            item["readable"] = False
        item["faculty"] = faculty_of(item["key"])
        item["lag_seconds"] = lag_seconds(item.pop("event_time"))
        notify(item, tid)
        item["metrics_published"] = publish(item["faculty"], item["lag_seconds"])
        processed.append(item)

    seconds = round(time.time() - started, 3)
    summary = {"trace_id": tid, "processed": len(processed), "skipped": skipped, "seconds": seconds}
    print("USMS_SUMMARY " + json.dumps(summary, sort_keys=True))
    return {"status": "ok", "version": "v2", "trace_id": tid, "seconds": seconds,
            "processed": processed, "skipped": skipped}
