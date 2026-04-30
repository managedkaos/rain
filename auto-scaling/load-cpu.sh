aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:asg-instance,Values=true" \
  --parameters 'commands=[
    "echo Starting background stress test...",
    "nohup stress-ng --cpu 2 --vm 1 --vm-bytes 512M --timeout 300s --metrics-brief > /tmp/stress-ng.log 2>&1 &",
    "echo stress-ng started in background. Check /tmp/stress-ng.log for output."
  ]' \
  --max-errors "1" \
  --comment "Run stress-ng in background on ASG instances"
