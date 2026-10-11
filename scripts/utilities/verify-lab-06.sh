#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/configs/course.env"   2>/dev/null || true
source "$REPO_ROOT/configs/lab-01.env"   2>/dev/null || true
source "$REPO_ROOT/configs/lab-02.env"   2>/dev/null || true
source "$REPO_ROOT/configs/lab-03.env"   2>/dev/null || true
source "$REPO_ROOT/configs/lab-04.env"   2>/dev/null || true
source "$REPO_ROOT/configs/lab-05.env"   2>/dev/null || true
source "$REPO_ROOT/configs/lab-06.env"   2>/dev/null || true

PASS=0; FAIL=0
check() {
  if eval "$2" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; PASS=$((PASS+1))
  else printf "  FAIL %s\n" "$1"; FAIL=$((FAIL+1)); fi
}

echo "== Environment =="
check "AWS CLI reaches Floci" "aws sts get-caller-identity"

echo "== Prerequisite: Lab 04 service still present =="
check "ECS cluster is ACTIVE" \
  "test \"\$(aws ecs describe-clusters --clusters $USMS_ECS_CLUSTER --query 'clusters[0].status' --output text)\" = ACTIVE"
check "enrolment service is ACTIVE" \
  "test \"\$(aws ecs describe-services --cluster $USMS_ECS_CLUSTER --services $USMS_ENROLMENT_SERVICE --query 'services[0].status' --output text)\" = ACTIVE"

echo "== Application Auto Scaling support (informational) =="
check "ASA confirmed unimplemented on this build (Path C)" \
  "aws application-autoscaling describe-scalable-targets --service-namespace ecs 2>&1 | grep -qiE 'UnknownOperation|Could not connect|InvalidAction' || ! aws application-autoscaling describe-scalable-targets --service-namespace ecs >/dev/null 2>&1"

echo "== CloudWatch custom metric (supported, built in this lab) =="
check "custom metric namespace USMS/Enrolment exists" \
  "aws cloudwatch list-metrics --namespace USMS/Enrolment --query 'Metrics[0].MetricName' --output text | grep -q EnrolmentQueueDepth"

echo "== CloudWatch alarm (supported, built in this lab) =="
check "alarm usms-enrolment-queue-high exists" \
  "aws cloudwatch describe-alarms --alarm-names usms-enrolment-queue-high --query 'MetricAlarms[0].AlarmName' --output text | grep -q usms-enrolment-queue-high"
check "alarm threshold is 100" \
  "test \"\$(aws cloudwatch describe-alarms --alarm-names usms-enrolment-queue-high --query 'MetricAlarms[0].Threshold' --output text)\" = 100.0"
check "alarm comparison is GreaterThanOrEqualToThreshold" \
  "test \"\$(aws cloudwatch describe-alarms --alarm-names usms-enrolment-queue-high --query 'MetricAlarms[0].ComparisonOperator' --output text)\" = GreaterThanOrEqualToThreshold"
check "alarm watches the EnrolmentQueueDepth metric" \
  "test \"\$(aws cloudwatch describe-alarms --alarm-names usms-enrolment-queue-high --query 'MetricAlarms[0].MetricName' --output text)\" = EnrolmentQueueDepth"

echo "== Deliverables on disk =="
check "lab-06 folder exists" "test -d labs/lab-06-ecs-autoscaling"
check "Lab 06 report exists" "test -f labs/lab-06-ecs-autoscaling/Report.md"

echo
echo "PASS=$PASS  FAIL=$FAIL"
echo
echo "Note: Application Auto Scaling is not implemented on this Floci build (Path C)."
echo "This script verifies the prerequisites, the confirmed ASA limitation, and the"
echo "CloudWatch metric + alarm that this build DOES support and that were built in"
echo "this lab. The scalable target, scaling policies and scheduled actions could not"
echo "be created on this emulator and are documented in the report instead."
[ "$FAIL" -eq 0 ]
