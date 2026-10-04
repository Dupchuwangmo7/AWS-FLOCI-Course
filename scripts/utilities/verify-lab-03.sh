#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-01.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-03.env" 2>/dev/null || true

: "${USMS_BASTION_ID:=none}"
: "${USMS_APP_ID:=none}"
: "${USMS_BASTION_SG:=none}"

PASS=0; FAIL=0
check() {
  if eval "$2" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; PASS=$((PASS+1))
  else printf "  FAIL %s\n" "$1"; FAIL=$((FAIL+1)); fi
}

echo "== Environment =="
check "Floci container running" \
  "test \"\$(docker container inspect $FLOCI_CONTAINER_NAME --format '{{.State.Running}}')\" = true"
check "AWS CLI reaches Floci" "aws sts get-caller-identity"

echo "== Lab 01 & 02 dependencies =="
check "instance profile usms-ec2-app-profile" \
  "aws iam get-instance-profile --instance-profile-name usms-ec2-app-profile"
check "VPC exists" "aws ec2 describe-vpcs --vpc-ids $USMS_VPC_ID"

echo "== Lab 03 instances =="
check "bastion instance exists" "aws ec2 describe-instances --instance-ids $USMS_BASTION_ID"
check "bastion is running" \
  "test \"\$(aws ec2 describe-instances --instance-ids $USMS_BASTION_ID --query 'Reservations[0].Instances[0].State.Name' --output text)\" = running"
check "bastion has public IP" \
  "test -n \"\$(aws ec2 describe-instances --instance-ids $USMS_BASTION_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)\""

check "app instance exists" "aws ec2 describe-instances --instance-ids $USMS_APP_ID"
check "app is running" \
  "test \"\$(aws ec2 describe-instances --instance-ids $USMS_APP_ID --query 'Reservations[0].Instances[0].State.Name' --output text)\" = running"
check "app has private IP" \
  "test -n \"\$(aws ec2 describe-instances --instance-ids $USMS_APP_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)\""
check "app has IAM instance profile" \
  "test -n \"\$(aws ec2 describe-instances --instance-ids $USMS_APP_ID --query 'Reservations[0].Instances[0].IamInstanceProfile' --output text)\""

echo "== Security groups =="
check "bastion-sg exists" "aws ec2 describe-security-groups --group-ids $USMS_BASTION_SG"
check "bastion-sg allows SSH from anywhere" \
  "aws ec2 describe-security-groups --group-ids $USMS_BASTION_SG --query 'SecurityGroups[0].IpPermissions[].FromPort' --output text | grep -qw 22"

echo "== Files =="
check "configs/lab-03.env exists" "test -f configs/lab-03.env"
check "configs/lab-03.env has no empty values" \
  "! grep -qE 'export [A-Z_]+=$|=None$' configs/lab-03.env"
check "key pair is ignored" \
  "git check-ignore -q outputs/usms-lab-key.pem"

echo; echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
