#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-04.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-05.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-09.env" 2>/dev/null || true
ACC="${USMS_ACCOUNT_ID:-000000000000}"
ESG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=usms-enrolment-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
ASG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=usms-alb-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
DSG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=usms-db-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
APSG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=usms-app-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
WEB=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=usms-web-01" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)

PASS=0; FAIL=0
check() { if eval "$2" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; PASS=$((PASS+1)); else printf "  FAIL %s\n" "$1"; FAIL=$((FAIL+1)); fi; }

echo "== Environment =="
check "AWS CLI reaches Floci" "aws sts get-caller-identity"

echo "== Identity: read-only policy and reader role =="
check "USMSStudentDataReadOnly exists" "aws iam get-policy --policy-arn arn:aws:iam::$ACC:policy/USMSStudentDataReadOnly"
check "RO policy denies PutObject" "aws iam get-policy-version --policy-arn arn:aws:iam::$ACC:policy/USMSStudentDataReadOnly --version-id v1 --query 'PolicyVersion.Document.Statement[?Effect==\`Deny\`].Action' --output text | grep -q PutObject"
check "usms-transcripts-reader-role exists" "aws iam get-role --role-name usms-transcripts-reader-role"
check "reader role carries the RO policy" "aws iam list-attached-role-policies --role-name usms-transcripts-reader-role --query 'AttachedPolicies[].PolicyName' --output text | grep -q USMSStudentDataReadOnly"
check "reader role trust has a Condition" "aws iam get-role --role-name usms-transcripts-reader-role --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output text | grep -q 000000000000"

echo "== Identity: confused-deputy fix on ecs-task-role =="
check "ecs-task-role trust now has a Condition" "aws iam get-role --role-name usms-ecs-task-role --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output text | grep -q 000000000000"
check "ecs-task-role still trusts ecs-tasks" "aws iam get-role --role-name usms-ecs-task-role --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' --output text | grep -q ecs-tasks"

echo "== Identity: deploy role, scoped PassRole, boundary =="
check "USMSPermissionsBoundary exists" "aws iam get-policy --policy-arn arn:aws:iam::$ACC:policy/USMSPermissionsBoundary"
check "boundary attached to NOTHING" "test -z \"\$(aws iam list-entities-for-policy --policy-arn arn:aws:iam::$ACC:policy/USMSPermissionsBoundary --query 'PolicyRoles[].RoleName' --output text)\""
check "USMSDeployBase exists" "aws iam get-policy --policy-arn arn:aws:iam::$ACC:policy/USMSDeployBase"
check "deploy PassRole is NOT on Resource *" "! aws iam get-policy-version --policy-arn arn:aws:iam::$ACC:policy/USMSDeployBase --version-id v1 --query 'PolicyVersion.Document.Statement[?Action==\`iam:PassRole\` && Effect==\`Allow\`].Resource' --output text | grep -qx '*'"
check "deploy PassRole denies passing to EC2" "aws iam get-policy-version --policy-arn arn:aws:iam::$ACC:policy/USMSDeployBase --version-id v1 --query 'PolicyVersion.Document.Statement[?Effect==\`Deny\`].Condition' --output text | grep -q ec2.amazonaws.com"
check "usms-deploy-role has a permissions boundary" "aws iam get-role --role-name usms-deploy-role --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text | grep -q USMSPermissionsBoundary"
check "usms-deploy-role trusts a user (not a service)" "aws iam get-role --role-name usms-deploy-role --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.AWS' --output text | grep -q user/"

echo "== Network: IMDSv2 =="
check "web-01 requires IMDSv2 tokens" "test \"\$(aws ec2 describe-instances --instance-ids $WEB --query 'Reservations[0].Instances[0].MetadataOptions.HttpTokens' --output text)\" = required"
check "web-01 hop limit is 1" "test \"\$(aws ec2 describe-instances --instance-ids $WEB --query 'Reservations[0].Instances[0].MetadataOptions.HttpPutResponseHopLimit' --output text)\" = 1"

echo "== Network: egress rules =="
check "enrolment-sg egress has a prefix-list (S3) rule" "aws ec2 describe-security-groups --group-ids $ESG --query 'SecurityGroups[0].IpPermissionsEgress[].PrefixListIds[0].PrefixListId' --output text | grep -q pl-"
check "alb-sg egress targets the enrolment SG" "aws ec2 describe-security-groups --group-ids $ASG --query 'SecurityGroups[0].IpPermissionsEgress[].UserIdGroupPairs[0].GroupId' --output text | grep -q $ESG"
check "db-sg egress has a tcp/443 rule" "aws ec2 describe-security-groups --group-ids $DSG --query 'SecurityGroups[0].IpPermissionsEgress[?FromPort==\`443\`]' --output text | grep -q 443"

echo "== Network: SSH narrowed =="
check "app-sg has a group-referenced SSH rule" "aws ec2 describe-security-groups --group-ids $APSG --query 'SecurityGroups[0].IpPermissions[?FromPort==\`22\`].UserIdGroupPairs[0].GroupId' --output text | grep -q sg-"

echo "== Audit scripts and files =="
check "usms-iam-audit.sh is executable" "test -x scripts/utilities/usms-iam-audit.sh"
check "configs/lab-09.env exists" "test -f configs/lab-09.env"
check "configs/lab-09.env has no empty values" "! grep -qE 'export [A-Z_]+=$|=None$' configs/lab-09.env"
check "all Lab 09 policy documents are valid JSON" "for f in policies/usms-student-data-ro-policy.json policies/trust-ecs-tasks-scoped.json policies/usms-permissions-boundary.json policies/usms-deploy-policy.json policies/trust-deploy.json policies/usms-enrolment-sg-egress.json policies/usms-alb-sg-egress.json policies/usms-db-sg-egress.json policies/usms-app-sg-ssh-bastion.json; do python3 -m json.tool \$f >/dev/null || exit 1; done"

echo; echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]