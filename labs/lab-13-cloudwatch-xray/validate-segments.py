#!/usr/bin/env python3
# validate-segments.py — structural checks on the three Lab 13 segment documents (X-Ray fallback).
import json, re
P = json.load(open("templates/lab-13-segment-parent.json"))
S = json.load(open("templates/lab-13-segment-subsegments.json"))
D = json.load(open("templates/lab-13-segment-downstream.json"))
hex16 = re.compile(r"^[0-9a-f]{16}$"); tidre = re.compile(r"^1-[0-9a-f]{8}-[0-9a-f]{24}$")
checks = [
 ("trace_id well-formed", bool(tidre.match(P["trace_id"]))),
 ("all three share the trace_id", P["trace_id"] == S["trace_id"] == D["trace_id"]),
 ("parent id is 16 hex", bool(hex16.match(P["id"]))),
 ("parent end_time > start_time", P["end_time"] > P["start_time"]),
 ("parent origin AWS::Lambda::Function", P.get("origin") == "AWS::Lambda::Function"),
 ("annotations faculty/stage/transcript_bytes/readable", set(P["annotations"]) >= {"faculty","stage","transcript_bytes","readable"}),
 ("3 subsegments with 16-hex ids, inside parent window",
   len(S["subsegments"]) == 3 and all(hex16.match(x["id"]) and S["start_time"] <= x["start_time"] < x["end_time"] <= S["end_time"] for x in S["subsegments"])),
 ("subsegment namespaces aws/remote/aws", [x["namespace"] for x in S["subsegments"]] == ["aws","remote","aws"]),
 ("downstream parent_id == parent id", D["parent_id"] == P["id"]),
 ("downstream type subsegment, origin AWS::S3::Bucket, HTTP 200",
   D["type"] == "subsegment" and D["origin"] == "AWS::S3::Bucket" and D["http"]["response"]["status"] == 200 and D["end_time"] > D["start_time"]),
]
for n, ok in checks: print(("  ok   " if ok else "  FAIL ") + n)
print("structural: %d/%d" % (sum(o for _, o in checks), len(checks)))
