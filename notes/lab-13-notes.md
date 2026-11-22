## Step 21 — composite alarm not supported by this Floci build
- aws CLI (JSON protocol): UnsupportedOperation "PutCompositeAlarm is not supported by CloudWatch JSON".
- Query protocol (form POST): UnsupportedOperation "... not supported by CloudWatch Query".
- Design kept in templates/lab-13-composite-alarm.json (aws cloudwatch put-composite-alarm --cli-input-json on AWS).
- DescribeAlarmHistory also unsupported (JSON); forced ALARM->OK proven by describe-alarms StateValue/StateReason instead.
