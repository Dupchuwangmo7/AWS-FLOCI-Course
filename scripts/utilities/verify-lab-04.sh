#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-01.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-03.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-04.env" 2>/dev/null || true

: "${USMS_DB_INSTANCE:=none}"
: "${USMS_DB_ENDPOINT:=none}"

PASS=0; FAIL=0
check() {
  if eval "$2" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; PASS=$((PASS+1))
  else printf "  FAIL %s\n" "$1"; FAIL=$((FAIL+1)); fi
}

echo "== Environment =="
check "Floci container running" \
  "test \"\$(docker container inspect $FLOCI_CONTAINER_NAME --format '{{.State.Running}}')\" = true"
check "AWS CLI reaches Floci" "aws sts get-caller-identity"

echo "== Lab 01, 02, 03 dependencies =="
check "instance profile usms-ec2-app-profile" \
  "aws iam get-instance-profile --instance-profile-name usms-ec2-app-profile"
check "VPC exists" "aws ec2 describe-vpcs --vpc-ids $USMS_VPC_ID"
check "app instance exists" "aws ec2 describe-instances --instance-ids $USMS_APP_ID"

echo "== Lab 04 RDS database =="
check "RDS instance exists" "aws rds describe-db-instances --db-instance-identifier $USMS_DB_INSTANCE"
check "RDS instance is available" \
  "test \"\$(aws rds describe-db-instances --db-instance-identifier $USMS_DB_INSTANCE --query 'DBInstances[0].DBInstanceStatus' --output text)\" = available"
check "RDS endpoint is populated" \
  "test -n \"$USMS_DB_ENDPOINT\""
check "RDS database name is usms_database" \
  "test \"\$(aws rds describe-db-instances --db-instance-identifier $USMS_DB_INSTANCE --query 'DBInstances[0].DBName' --output text)\" = usms_database"
check "RDS has security group attached" \
  "aws rds describe-db-instances --db-instance-identifier $USMS_DB_INSTANCE --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text | grep -q sg-"

echo "== Security & Access =="
check "RDS is NOT publicly accessible" \
  "test \"\$(aws rds describe-db-instances --db-instance-identifier $USMS_DB_INSTANCE --query 'DBInstances[0].PubliclyAccessible' --output text)\" = False"
check "DB SG exists and has PostgreSQL rules" \
  "aws ec2 describe-security-groups --group-ids $USMS_DB_SG --query 'SecurityGroups[0].IpPermissions[].FromPort' --output text | grep -qE '5432|7001'"

echo "== Files =="
check "configs/lab-04.env exists" "test -f configs/lab-04.env"
check "configs/lab-04.env has no empty values" \
  "! grep -qE 'export [A-Z_]+=$|=None$' configs/lab-04.env"

echo; echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
