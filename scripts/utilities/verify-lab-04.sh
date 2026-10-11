#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0
check() {
  if eval "$2" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; PASS=$((PASS+1))
  else printf "  FAIL %s\n" "$1"; FAIL=$((FAIL+1)); fi
}

source configs/lab-04.env

echo "== Environment =="
check "Floci container running" \
  "test \"\$(docker container inspect $FLOCI_CONTAINER_NAME --format '{{.State.Running}}')\" = true"
check "AWS CLI reaches Floci" "aws sts get-caller-identity"

echo "== Lab 01 to 03 dependencies =="
check "usms-app-sg still exists" "aws ec2 describe-security-groups --group-ids $USMS_APP_SG"
check "usms-private-subnet-a exists" "aws ec2 describe-subnets --subnet-ids $USMS_PRIVATE_SUBNET_A"
check "usms-private-subnet-b exists" "aws ec2 describe-subnets --subnet-ids $USMS_PRIVATE_SUBNET_B"
check "private rt still has NO igw route" \
  "! aws ec2 describe-route-tables --route-table-ids ${USMS_PRIVATE_RT:-none} --query 'RouteTables[0].Routes[].GatewayId' --output text | grep -q 'igw-'"
check "USMSStudentDataReadWrite policy exists" \
  "aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/USMSStudentDataReadWrite"

echo "== Lab 04 ECS =="
check "cluster usms-ecs-cluster is ACTIVE" \
  "test \"\$(aws ecs describe-clusters --clusters $USMS_ECS_CLUSTER --query 'clusters[0].status' --output text)\" = ACTIVE"
check "service usms-enrolment-svc is ACTIVE" \
  "test \"\$(aws ecs describe-services --cluster $USMS_ECS_CLUSTER --services $USMS_ENROLMENT_SERVICE --query 'services[0].status' --output text)\" = ACTIVE"
check "service desiredCount is $USMS_ECS_DESIRED_BASELINE" \
  "test \"\$(aws ecs describe-services --cluster $USMS_ECS_CLUSTER --services $USMS_ENROLMENT_SERVICE --query 'services[0].desiredCount' --output text)\" = $USMS_ECS_DESIRED_BASELINE"

echo "== Files =="
check "configs/lab-04.env exists" "test -f configs/lab-04.env"
check "configs/lab-04.env has no empty values" \
  "! grep -qE 'export [A-Z_]+=$|=None$' configs/lab-04.env"

echo; echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]