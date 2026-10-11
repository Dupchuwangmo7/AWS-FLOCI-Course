# Lab 06 — Implementing Auto Scaling for the ECS Enrolment Service

## 1. Headline result and support path

This Floci build **does not implement the Application Auto Scaling service**, so the core of the lab (scalable target, scaling policies, scheduled actions, scaling activities) could not be created. This is the lab's documented **Path C** (Step 3: "no Application Auto Scaling"). The CloudWatch portion of the lab — a custom metric and an alarm — **is** supported and was built and exercised successfully.

Evidence of the limitation, captured directly from the environment:

```
$ aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id "service/usms-ecs-cluster/usms-enrolment-svc" \
    --scalable-dimension "ecs:service:DesiredCount" \
    --min-capacity 2 --max-capacity 10

An error occurred (UnknownOperationException) when calling the RegisterScalableTarget operation:
Unknown operation: AnyScaleFrontendService.RegisterScalableTarget
```

Capability probe result for this build:

| API | Operation | Supported on this build |
|---|---|---|
| Application Auto Scaling | `describe-scalable-targets` | No |
| Application Auto Scaling | `register-scalable-target` | No (rejected at call time) |
| Application Auto Scaling | `describe-scaling-policies` | No |
| Application Auto Scaling | `put-scaling-policy` | No |
| Application Auto Scaling | `describe-scheduled-actions` | No |
| Application Auto Scaling | `describe-scaling-activities` | No |
| CloudWatch | `describe-alarms` | Yes |
| CloudWatch | `put-metric-alarm` | Yes |
| CloudWatch | `put-metric-data` | Yes |
| CloudWatch | `set-alarm-state` | Yes |
| CloudWatch | `list-metrics` | Yes |

(The `--generate-cli-skeleton` forms of the Application Auto Scaling writes returned "supported" because the skeleton is produced by the local CLI model, not the emulator; the live call is what reveals the service is absent.)

## 2. What was actually built (CloudWatch, supported)

The step-scaling half of the lab depends on a CloudWatch alarm watching a custom metric. That alarm and metric are pure CloudWatch and work on this build, so they were created and exercised in full.

**Custom metric** — `USMS/Enrolment` namespace, `EnrolmentQueueDepth`:

```
aws cloudwatch put-metric-data --namespace "USMS/Enrolment" \
  --metric-name EnrolmentQueueDepth --value 42 --unit Count
# further points published: 85, 150
```

Confirmed via `list-metrics`:

```
-------------------------------------------
|               ListMetrics               |
+-----------------+-----------------------+
|       NS        |         Name          |
+-----------------+-----------------------+
|  USMS/Enrolment |  EnrolmentQueueDepth  |
+-----------------+-----------------------+
```

**Alarm** — `usms-enrolment-queue-high`, the alarm that would drive the step-scaling policy:

```
aws cloudwatch put-metric-alarm \
  --alarm-name usms-enrolment-queue-high \
  --namespace "USMS/Enrolment" --metric-name EnrolmentQueueDepth \
  --statistic Average --period 60 --evaluation-periods 1 \
  --threshold 100 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching
```

Read-back on creation: threshold `100.0`, state `INSUFFICIENT_DATA` (correct for a new alarm before its first evaluation period completes).

**Alarm wiring proof** — driving the alarm into ALARM state deliberately:

```
aws cloudwatch set-alarm-state --alarm-name usms-enrolment-queue-high \
  --state-value ALARM --state-reason "simulating queue depth >= 100"
# read-back: State = ALARM
```

On real AWS, this state transition is exactly the event that invokes a step-scaling policy. On this build the transition is honoured by CloudWatch, so the alarm side of the wiring is demonstrable even though the policy it would invoke cannot exist. The alarm was reset to `OK` afterwards.

## 3. The scaling design (what would have been built on AWS)

Although the Application Auto Scaling objects could not be created, the design is the substance of the lab and is recorded here in full.

### 3.1 Scalable target
- **Address:** namespace `ecs`, resource ID `service/usms-ecs-cluster/usms-enrolment-svc`, dimension `ecs:service:DesiredCount`.
- **Bounds:** min 2, max 10.
- **Floor rationale:** two tasks, one per Availability Zone, so losing a zone costs half the capacity rather than all of it (carried from Lab 04). The floor is a latency decision, not a cost decision — it is the capacity that absorbs the first two minutes of any spike before a reactive policy can react.
- **Ceiling rationale:** a guard against a runaway policy or a misbehaving metric, and against exhausting the private-subnet address space.

### 3.2 Target-tracking policy — CPU
- Metric `ECSServiceAverageCPUUtilization`, target `50.0`.
- `ScaleOutCooldown` 60s, `ScaleInCooldown` 300s, `DisableScaleIn` false.
- Reasoning: scale out fast, scale in slowly. Scaling out too eagerly costs money; scaling in too eagerly costs availability, and the second mistake is the expensive one. The AWS default is 300s for both — the asymmetry here is a deliberate choice.
- Caveat: Fargate `CPUUtilization` is a percentage of the task's *reserved* CPU, not a physical core, so the target is only meaningful relative to the task's 256-unit reservation.

### 3.3 Target-tracking policy — requests
- Metric `ALBRequestCountPerTarget`, target `1000`.
- This is the better signal for a web API because it measures the work the service actually does, and it is only possible because Lab 05 built the ALB and target group. It requires a `ResourceLabel` built from the ALB and target-group ARNs:
  `app/usms-enrolment-alb/3b116a4aed034c22/targetgroup/usms-enrolment-tg/084623283e59443d`.
- Note on correctness: the predefined metric is *per target* (`RequestCountPerTarget`), not total request count. Target tracking only works on a metric that falls as capacity rises; total request count does not fall when tasks are added, so using it would drive the policy to the ceiling and hold it there.

### 3.4 Step-scaling policy — queue depth
- Driven by the `usms-enrolment-queue-high` alarm on the custom `EnrolmentQueueDepth` metric (built above).
- Step adjustments: backlog 100–200 → +1 task; backlog 200+ → +3 tasks.
- Reasoning: step scaling expresses a response that is a *function of how bad things are*, which target tracking (a single set point) cannot. It is also the policy type where you own the alarm.

### 3.5 Scheduled actions
- Weekday 07:45 Asia/Thimphu → min 4; weekday 20:00 Asia/Thimphu → min 2.
- Reasoning: enrolment opens at a known time. A reactive policy only learns about the spike after it starts; a scheduled action raises the floor *before* the load arrives. Scheduled scaling is the only mechanism that can be early. (Predictive scaling is not available for ECS — it exists only in EC2 Auto Scaling — so a scheduled action is the correct tool here.)

### 3.6 Suspension model
- Three independent switches: `DynamicScalingInSuspended`, `DynamicScalingOutSuspended`, `ScheduledScalingSuspended`. All should be left `false`; a switch left suspended is a silent fault.


## 4. The central idea

Application Auto Scaling writes **one integer** — `desiredCount`. It does not start tasks, talk to containers, or know a load balancer exists. It reads a metric, compares it with a target, and writes the number. Everything downstream — ECS starting a task, the task getting an ENI in a private subnet, the service registering it in the Lab 05 target group, the ALB health-checking it — is machinery already built in Labs 02–05. On this emulator the decision-making layer is absent, but the machinery it would drive is present and was verified in the earlier labs.

## 5. Floci vs real AWS (what this lab revealed about the tooling)

| Aspect | Real AWS | This Floci build |
|---|---|---|
| Application Auto Scaling API | Full control loop across 5 services | Not implemented (`UnknownOperationException`) |
| `register-scalable-target` | Creates a registration, enforces bounds | Rejected at call time |
| Scaling policies / scheduled actions | Created, evaluated every minute | Cannot be created |
| Scaling activities | Recorded with a cause string | None |
| CloudWatch custom metrics | Supported | Supported (verified) |
| CloudWatch alarms + `set-alarm-state` | Supported; state change invokes policy | Supported; state change honoured, but no policy to invoke |

The honest summary: the *decision layer* of auto scaling is absent on this build, while the *observability layer* it depends on (CloudWatch metrics and alarms) is present. The design, the metric, and the alarm were all produced; the policies and the closed scaling loop were not possible and were not faked.


## 6. Outcome

- Documented Path C with the exact server error as evidence.
- Built and verified the CloudWatch custom metric `USMS/Enrolment EnrolmentQueueDepth`.
- Built the `usms-enrolment-queue-high` alarm (threshold 100, GreaterThanOrEqualToThreshold) and demonstrated its state transition to ALARM.
- Recorded the full scaling design — scalable target bounds, two target-tracking policies, one step-scaling policy, two scheduled actions, and the suspension model — with the reasoning behind each decision.


