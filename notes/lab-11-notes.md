# Lab 11 notes

Support path: A - codebuild, codepipeline, ecr and codedeploy all answered the probe.
(Whether builds actually execute is tested in Step 12.)

## Step 12–13 — does Floci really execute builds? (proven)
- Plain python:3.12-slim alias: container lived ~56 ms (default CMD python3 exits) -> nothing ran.
- Rebuilt alias as python:3.12-slim + CMD ["sleep","infinity"] tagged aws/codebuild/standard:7.0.
- Negative probe :3 (buildspec-override echo PROBE-RAN; exit 1) -> FAILED, msg "Exit code 1: PROBE-RAN".
- Source probe :5 -> PWD=/codebuild/output/src/src VERSION=r3, files buildspec.yml config src tests.
- Tool probe :6 -> CONFIG-OK, dist built (healthz.html index.html).
- Real build :4 -> SUCCEEDED, all phases (incl. pre_build grep checks + post_build smoke).
- Floci gaps: no CloudWatch log events (count 0), no S3 artifact upload (bucket has only source/).
  Command output only surfaces in a failed phase's context message.

## CORRECTION + Steps 18–20 (proven)
- Floci never reads buildspec.yml from the source: the project's buildspec field is treated as
  inline YAML ("buildspec.yml" = no phases -> empty run -> SUCCEEDED). So builds :4 :8 :15
  ran nothing. Commands only run when the buildspec is passed inline (--buildspec-override).
- Floci ignores --source-type-override / --source-location-override (probe :14 FILES=[]).
- Floci accepted a plain start-build on a CODEPIPELINE project (:7); AWS would reject it.
- Pipeline (Path A for the API): executions reach Succeeded; Source picks up the uploaded
  VersionId; Build triggers a CodeBuild build (:9 r4, :10 r5, :11 v2). BUT Floci does not hand
  SourceOutput to CodeBuild (probe :13 FILES=[] BUILDSPEC=no), so pipeline builds run empty and
  the v2 failure was NOT caught by the pipeline. No BuildOutput object is written.
- Step 20 shown on Floci CodeBuild with project on S3 source + real buildspec inline:
  :16 v2 -> FAILED at PRE_BUILD (grep container check); :17 fixed -> SUCCEEDED;
  :18 -> smoke 7/7, release r5, buildId usms-enrolment-build:18 (in-CodeBuild metadata proof).
- Local runner: v2 -> PRE_BUILD #3 exit 1; fixed -> 7/7 exit 0.
