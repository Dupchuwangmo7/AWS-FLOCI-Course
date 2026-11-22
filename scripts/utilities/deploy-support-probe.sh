#!/usr/bin/env bash
# deploy-support-probe.sh — what deployment surface does this emulator offer?
# Writes outputs/lab-12-deploy-probe.txt with USMS_CICD_DEPLOY_PATH and USMS_CODEDEPLOY_SUPPORTED.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$REPO_ROOT/outputs/lab-12-deploy-probe.txt"
ok() { "$@" >/dev/null 2>&1; }

DOCKER=NO;  ok docker info && DOCKER=YES
ECR_LIST=NO; ok aws ecr describe-repositories && ECR_LIST=YES
ECR_CREATE=NO
if ok aws ecr create-repository --repository-name usms-probe-delete-me; then
  ECR_CREATE=YES
  aws ecr delete-repository --repository-name usms-probe-delete-me --force >/dev/null 2>&1
fi
ECS=NO;     ok aws ecs list-clusters && ECS=YES
CODEDEPLOY=NO; ok aws deploy list-applications && CODEDEPLOY=YES

if [ $DOCKER = YES ] && [ $ECR_LIST = YES ] && [ $ECR_CREATE = YES ] && [ $ECS = YES ]; then PATH_=A
elif [ $DOCKER = YES ] && [ $ECS = YES ]; then PATH_=B
else PATH_=C; fi

{
  echo "# Lab 12 deploy support probe — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "docker daemon reachable        : $DOCKER"
  echo "ecr describe-repositories      : $ECR_LIST"
  echo "ecr create/delete-repository   : $ECR_CREATE"
  echo "ecs list-clusters              : $ECS"
  echo "deploy list-applications       : $CODEDEPLOY"
  echo "USMS_CICD_DEPLOY_PATH=$PATH_"
  echo "USMS_CODEDEPLOY_SUPPORTED=$( [ $CODEDEPLOY = YES ] && echo true || echo false )"
} | tee "$OUT"
