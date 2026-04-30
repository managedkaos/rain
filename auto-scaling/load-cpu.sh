#!/usr/bin/env bash
set -euo pipefail

INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:role,Values=webserver" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
  echo "No running EC2 instances found with tag role=webserver." >&2
  exit 1
fi

aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids $INSTANCE_IDS \
  --parameters 'commands=[
    "echo Starting background stress test...",
    "nohup stress-ng --cpu 2 --vm 1 --vm-bytes 512M --timeout 300s --metrics-brief > /tmp/stress-ng.log 2>&1 &",
    "echo stress-ng started in background. Check /tmp/stress-ng.log for output."
  ]' \
  --max-errors "1" \
  --comment "Run stress-ng in background on ASG instances"
