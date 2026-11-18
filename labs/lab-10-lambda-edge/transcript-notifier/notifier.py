"""usms-transcript-notifier

Regional Lambda, triggered by S3 ObjectCreated on usms-student-data.
Stays inside USMSLambdaBasic (CloudWatch Logs + s3:GetObject). When the SNS lab
arrives, notify() becomes a real publish and the policy grows by one action.
"""

import json
import os
import urllib.parse

BUCKET_HINT = os.environ.get("USMS_BUCKET", "usms-student-data")
CHANNEL = os.environ.get("USMS_NOTIFY_CHANNEL", "stdout")


def describe(record):
    """Pull the four fields that matter out of one S3 event record."""
    s3 = record.get("s3", {})
    raw_key = s3.get("object", {}).get("key", "")
    return {
        "event": record.get("eventName"),
        "bucket": s3.get("bucket", {}).get("name"),
        # S3 URL-encodes keys in events; unquote_plus restores the real key.
        "key": urllib.parse.unquote_plus(raw_key),
        "size": s3.get("object", {}).get("size"),
    }


def notify(payload):
    """Today: a structured stdout line that CloudWatch Logs captures."""
    print("USMS_NOTIFY " + json.dumps(payload, sort_keys=True))


def handler(event, context):
    records = event.get("Records", [])
    print("usms-transcript-notifier: %d record(s), channel=%s, bucket_hint=%s"
          % (len(records), CHANNEL, BUCKET_HINT))

    processed = []
    for record in records:
        info = describe(record)
        if not info["key"].startswith("transcripts/"):
            print("skipping non-transcript object: %s" % info["key"])
            continue

        # Exercise s3:GetObject; wrapped because the emulator may not give the
        # container a route back to the S3 API.
        info["readable"] = False
        try:
            import boto3
            boto3.client("s3").head_object(Bucket=info["bucket"], Key=info["key"])
            info["readable"] = True
        except Exception as exc:  # noqa: BLE001
            info["read_error"] = type(exc).__name__

        notify(info)
        processed.append(info["key"])

    return {"processed": len(processed), "keys": processed}
