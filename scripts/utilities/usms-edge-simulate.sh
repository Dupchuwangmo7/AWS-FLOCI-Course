#!/usr/bin/env bash
# Run the USMS edge chain the way CloudFront would, using direct Lambda
# invocations in place of a request path Floci does not have.
#   viewer-request fn --> (deny? stop) --> origin (simulated) --> origin-response fn
# Usage: usms-edge-simulate.sh [viewer-request-event.json]
# Writes: outputs/lab-10-edge-trace.json
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
export EVENT="${1:-templates/lab-10-viewer-request-event.json}"
[ -f "$EVENT" ] || { echo "no such event file: $EVENT" >&2; exit 1; }
python3 - << 'PY'
import json, os, subprocess, sys
def invoke(fn, payload_file, out):
    r = subprocess.run(["aws", "lambda", "invoke", "--function-name", fn,
                        "--payload", "fileb://" + payload_file, out],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("invoke failed: " + r.stderr)
    return json.load(open(out))
trace = "outputs/lab-10-edge-trace.json"

print("== 1. viewer-request ==")
step1 = invoke("usms-edge-viewer-request", os.environ["EVENT"], "outputs/.edge-step1.json")
if "status" in step1:                      # a RESPONSE came back: CloudFront stops here
    print("   decision: DENY - the origin is never contacted")
    result = {"chain": ["viewer-request"], "decision": "deny", "status": step1.get("status"),
              "headers": {k: v[0]["value"] for k, v in step1.get("headers", {}).items()}}
else:                                      # a REQUEST came back: continue to the origin
    print("   decision: ALLOW - uri is now " + step1["uri"])
    print("== 2. origin (simulated: what the bucket would have returned) ==")
    event = {"Records": [{"cf": {
        "config": {"distributionId": "SIMULATED", "eventType": "origin-response", "requestId": "edge-simulate"},
        "request": step1,
        "response": {"status": "200", "statusDescription": "OK", "headers": {
            "content-type": [{"key": "Content-Type", "value": "application/json"}],
            "server": [{"key": "Server", "value": "AmazonS3"}]}}}}]}
    json.dump(event, open("outputs/.edge-step2-event.json", "w"))
    print("   built an origin-response event carrying the modified request")
    print("== 3. origin-response ==")
    step3 = invoke("usms-edge-origin-response", "outputs/.edge-step2-event.json", "outputs/.edge-step3.json")
    result = {"chain": ["viewer-request", "origin", "origin-response"], "decision": "allow",
              "request_uri_after_normalisation": step1["uri"], "status": step3["status"],
              "headers": {k: v[0]["value"] for k, v in step3["headers"].items()}}

out = json.dumps(result, indent=2)
print(out)
open(trace, "w").write(out + "\n")
for f in ["outputs/.edge-step1.json", "outputs/.edge-step2-event.json", "outputs/.edge-step3.json"]:
    if os.path.exists(f): os.remove(f)
print("\ntrace written to " + trace)
PY
