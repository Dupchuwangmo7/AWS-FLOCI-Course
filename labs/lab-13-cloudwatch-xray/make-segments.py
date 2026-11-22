#!/usr/bin/env python3
# make-segments.py — write the three Lab 13 X-Ray segment documents (one trace) into templates/.
import json, os, secrets, time
now = time.time()
tid = "1-%08x-%s" % (int(now), secrets.token_hex(12))
pid = secrets.token_hex(8)
t0 = round(now - 1.2, 3)
def sub(name, ns, a, b, **extra):
    d = {"id": secrets.token_hex(8), "name": name, "namespace": ns, "start_time": round(t0 + a, 3), "end_time": round(t0 + b, 3)}
    d.update(extra); return d
annotations = {"faculty": "science", "stage": "notify", "transcript_bytes": 64, "readable": True}
metadata = {"usms": {"bucket": "usms-student-data", "key": "transcripts/science/lab-13-probe.json", "lab": 13}}
parent = {"name": "usms-transcript-notifier", "id": pid, "trace_id": tid, "start_time": t0, "end_time": round(t0 + 0.91, 3),
          "origin": "AWS::Lambda::Function", "annotations": annotations, "metadata": metadata}
with_subs = dict(parent, subsegments=[
    sub("s3-head-object", "aws", 0.02, 0.09, aws={"operation": "HeadObject"}),
    sub("render-pdf", "remote", 0.10, 0.80),
    sub("cloudwatch-put-metric-data", "aws", 0.81, 0.88, aws={"operation": "PutMetricData"})])
down = {"name": "usms-student-data", "id": secrets.token_hex(8), "trace_id": tid, "parent_id": pid, "type": "subsegment",
        "origin": "AWS::S3::Bucket", "namespace": "aws", "start_time": round(t0 + 0.02, 3), "end_time": round(t0 + 0.09, 3),
        "http": {"response": {"status": 200}}}
for f, d in [("parent", parent), ("subsegments", with_subs), ("downstream", down)]:
    json.dump(d, open("templates/lab-13-segment-%s.json" % f, "w"), indent=2)
with open("outputs/lab-13-trace-ids.txt", "a") as fh:
    fh.write("%s %s %s\n" % (tid, pid, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())))
print("trace_id", tid, "parent", pid)
