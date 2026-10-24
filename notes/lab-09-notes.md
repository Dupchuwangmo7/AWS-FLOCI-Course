# Lab 09 notes

Support path: B (management only)
- All IAM read/write operations supported (create-role, create-policy, update-assume-role-policy, permissions-boundary)
- simulate-principal-policy NOT available (expected on Path B; proof is by reading documents)
- All EC2 rule + metadata operations supported
- Floci enforces neither IAM nor security groups; every proof is by reading configuration.

Bucket usms-student-data did not exist yet at Step 6 (Lab 10 creates it) - head-bucket expected to fail.

Step 5 audit baseline: HIGH=6 MED=29 roles=7 (6 confused-deputy service-trust findings; MED mostly Resource:* on EKS ENI/ELB ops + no boundaries)
Step 6: USMSStudentDataReadWrite grants GetObject + PutObject + DeleteObject on /*; the read-only workload needs only GetObject (+ListBucket). Read-only policy drops PutObject and DeleteObject. Bucket usms-student-data returns 404 (Lab 10 creates it).
Step 7: Created USMSStudentDataReadOnly (Get+List, explicit Deny on writes) + usms-transcripts-reader-role (scoped ecs-tasks trust). Rewrote usms-ecs-task-role trust: SAME PRINCIPAL, NEW CONDITION (confused-deputy fixed). Undo saved.
Step 11-16: IMDSv2 required (hop 1) on web-01; egress scoped on enrolment-sg (443->S3 pl-63a5400a), alb-sg (80->enrolment-sg), db-sg (443 out); SSH on app-sg narrowed to bastion-sg sg-c6deb3895f4fe63c6.
