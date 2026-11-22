## Step 11 — tasks never started (stale subnets)
- Floci log: "Service reconciler failed to start task ... subnet 'subnet-e726cf6c' does not exist".
- Service awsvpc subnets were from before the Floci data-loss rebuild (commit 5a5f76c).
- Repaired with update-service --network-configuration -> subnet-6739a4fc, subnet-09571447 (sg-33f7f9db3cd53212f).
## Steps 17–18 — deploy and rollback drill
- Pipeline Deploy stage FAILED: "Provider ECS is not available in Floci CodePipeline".
  Deploy done by hand as the provider would: dist/imagedefinitions.json -> register :3 (r7) -> update-service.
- :3 r7 STABLE 2/2, containers on digest 01f34025... (= ECR r7).
- Drill: :4 points at r8 (never pushed). Floci: "failed to resolve reference ...:r8: not found";
  deployment IN_PROGRESS 0/2, no circuit-breaker rollback (stored, not enforced); old r7 tasks kept serving.
- Rolled back by hand to :3 -> STABLE in ~10 s.
- Decision: deregistered usms-enrolment:4 — it names an image that does not exist, so it can only ever
  fail; leaving it ACTIVE invites someone to redeploy it.
- Revision numbers are one lower than the lab (:3 good, :4 bad) because Lab 04's :2 never existed after
  the Floci data-loss rebuild; memory is 512 (course baseline), not 1024.
