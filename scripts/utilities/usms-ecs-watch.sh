#!/usr/bin/env bash
# usms-ecs-watch.sh <cluster> <service> [iterations=20]
# Polls describe-services every 10 s. Exits 0 when there is exactly one deployment and the
# PRIMARY deployment's runningCount equals desiredCount; exits 1 if that never happens.
# Used instead of `aws ecs wait services-stable`, which can exhaust silently on Floci.
set -uo pipefail
CLUSTER="${1:?usage: usms-ecs-watch.sh <cluster> <service> [iterations]}"
SERVICE="${2:?usage: usms-ecs-watch.sh <cluster> <service> [iterations]}"
ITER="${3:-20}"
for i in $(seq 1 "$ITER"); do
  read -r NDEP PRUN PDES PTD <<<"$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].[length(deployments), deployments[?status==`PRIMARY`]|[0].runningCount, deployments[?status==`PRIMARY`]|[0].desiredCount, deployments[?status==`PRIMARY`]|[0].taskDefinition]' \
    --output text)"
  printf '%s  [%2d/%d] deployments=%s primary running=%s desired=%s  %s\n' \
    "$(date +%T)" "$i" "$ITER" "$NDEP" "$PRUN" "$PDES" "${PTD##*/}"
  if [ "$NDEP" = "1" ] && [ "$PRUN" = "$PDES" ]; then echo "STABLE"; exit 0; fi
  [ "$i" -lt "$ITER" ] && sleep 10
done
echo "NOT STABLE after $ITER polls"
exit 1
