#!/usr/bin/env bash
# usms-emit-telemetry.sh [faculty] [seconds]
#
# Emits one coherent piece of USMS telemetry for a processed transcript:
#   1 log event    USMS_EVENT line in /usms/central/application (stream lab-13-YYYYMMDD)
#   2 metric points TranscriptsProcessed{Faculty,Stage=notify}=1 and TranscriptLagSeconds{Stage=notify}=<seconds>
#   1 trace segment usms-transcript-notifier with annotations faculty/stage
# If X-Ray is not available (Floci), the segment is validated and appended to
# outputs/lab-13-emitted-segments.jsonl instead, and the script says so.
set -uo pipefail

FACULTY="${1:-science}"
LAG="${2:-0.5}"
case "$FACULTY" in ""|*[!a-z]*) echo "ERROR: faculty must be lowercase letters (got '$FACULTY')" >&2; exit 2 ;; esac
[ "${#FACULTY}" -le 20 ] || { echo "ERROR: faculty longer than 20 characters" >&2; exit 2; }
python3 -c "import sys; float(sys.argv[1])" "$LAG" 2>/dev/null || { echo "ERROR: seconds must be a number (got '$LAG')" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GROUP=/usms/central/application
STREAM="lab-13-$(date -u +%Y%m%d)"
NS=USMS/Application
TMP="$(mktemp -d "${TMPDIR:-/tmp}/usms-emit.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# 1. log event
aws logs create-log-stream --log-group-name "$GROUP" --log-stream-name "$STREAM" >/dev/null 2>&1 || true
python3 - "$FACULTY" "$LAG" > "$TMP/events.json" <<'PY'
import json, sys, time
faculty, lag = sys.argv[1], float(sys.argv[2])
msg = "USMS_EVENT " + json.dumps({"event": "transcript.processed", "student": "stu-emit",
                                  "faculty": faculty, "seconds": lag, "source": "usms-emit-telemetry"})
print(json.dumps([{"timestamp": int(time.time() * 1000), "message": msg}]))
PY
if aws logs put-log-events --log-group-name "$GROUP" --log-stream-name "$STREAM" \
     --log-events "file://$TMP/events.json" >/dev/null; then
  echo "log     ok   $GROUP/$STREAM"
else
  echo "log     FAIL put-log-events" >&2
fi

# 2. metric points
if aws cloudwatch put-metric-data --namespace "$NS" --metric-name TranscriptsProcessed --unit Count --value 1 \
     --dimensions "Faculty=$FACULTY,Stage=notify" &&
   aws cloudwatch put-metric-data --namespace "$NS" --metric-name TranscriptLagSeconds --unit Seconds --value "$LAG" \
     --dimensions Stage=notify; then
  echo "metric  ok   TranscriptsProcessed{Faculty=$FACULTY,Stage=notify}=1  TranscriptLagSeconds{Stage=notify}=$LAG"
else
  echo "metric  FAIL put-metric-data" >&2
fi

# 3. trace segment
python3 - "$FACULTY" "$LAG" > "$TMP/segment.json" <<'PY'
import json, secrets, sys, time
faculty, lag = sys.argv[1], float(sys.argv[2])
now = time.time()
print(json.dumps({
    "name": "usms-transcript-notifier", "id": secrets.token_hex(8),
    "trace_id": "1-%08x-%s" % (int(now), secrets.token_hex(12)),
    "start_time": round(now - lag, 3), "end_time": round(now, 3),
    "origin": "AWS::Lambda::Function",
    "annotations": {"faculty": faculty, "stage": "emit", "lag_seconds": lag},
}))
PY
TRACE_ID="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['trace_id'])" "$TMP/segment.json")"
mkdir -p "$REPO_ROOT/outputs"
if aws xray put-trace-segments --trace-segment-documents "$(cat "$TMP/segment.json")" >/dev/null 2>&1; then
  echo "trace   ok   $TRACE_ID (sent to X-Ray)"
else
  cat "$TMP/segment.json" >> "$REPO_ROOT/outputs/lab-13-emitted-segments.jsonl"
  echo "trace   local $TRACE_ID (X-Ray unavailable: segment recorded in outputs/lab-13-emitted-segments.jsonl)"
fi
echo "$TRACE_ID emit faculty=$FACULTY seconds=$LAG $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REPO_ROOT/outputs/lab-13-trace-ids.txt"
