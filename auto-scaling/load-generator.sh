#!/usr/bin/env bash
set -euo pipefail

DURATION=300
RUN_CPU=false
RUN_REQUESTS=false
REQUEST_COUNT=1000000
CONCURRENCY=200

usage() {
  cat <<USAGE
Usage: $0 [--duration SECONDS] [--cpu] [--requests [COUNT]] [--concurrency COUNT]

Options:
  --duration SECONDS    Amount of time to sustain load. Defaults to 300.
  --cpu                 Generate CPU load on running instances tagged role=webserver.
  --requests [COUNT]    Generate request load from the load generator instance. Defaults to 1000000.
  --concurrency COUNT   Apache Bench concurrency for request load. Defaults to 200.
  -h, --help            Show this help.
USAGE
}

require_positive_integer() {
  local key=$1
  local value=$2

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "$key must be a positive integer." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      if [[ $# -lt 2 ]]; then
        echo "--duration requires a value." >&2
        exit 1
      fi
      DURATION=$2
      shift 2
      ;;
    --cpu)
      RUN_CPU=true
      shift
      ;;
    --requests)
      RUN_REQUESTS=true
      if [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
        REQUEST_COUNT=$2
        shift 2
      else
        shift
      fi
      ;;
    --concurrency)
      if [[ $# -lt 2 ]]; then
        echo "--concurrency requires a value." >&2
        exit 1
      fi
      CONCURRENCY=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_positive_integer "--duration" "$DURATION"
require_positive_integer "--requests" "$REQUEST_COUNT"
require_positive_integer "--concurrency" "$CONCURRENCY"

if [[ "$RUN_CPU" == false && "$RUN_REQUESTS" == false ]]; then
  printf "\nNo load type selected: choose at least one or both: --cpu, --requests\n\n" >&2
  usage >&2
  exit 1
fi

run_cpu_load() {
  local instance_ids_output
  local -a instance_ids

  instance_ids_output=$(aws ec2 describe-instances \
    --filters "Name=tag:role,Values=webserver" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)
  read -r -a instance_ids <<< "$instance_ids_output"

  if [[ ${#instance_ids[@]} -eq 0 ]]; then
    echo "No running EC2 instances found with tag role=webserver." >&2
    exit 1
  fi

  aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "${instance_ids[@]}" \
    --parameters "commands=[
      \"echo Starting background stress test for ${DURATION} seconds...\",
      \"nohup stress-ng --cpu 0 -l 85 --vm 1 --timeout ${DURATION}s --metrics-brief > /tmp/stress-ng.log 2>&1 &\",
      \"echo stress-ng started in background. Check /tmp/stress-ng.log for output.\"
    ]" \
    --max-errors "1" \
    --comment "Run stress-ng in background on ASG instances"
}

get_load_generator_instance_id() {
  aws ec2 describe-instances \
    --filters \
      "Name=tag:asg-load-generator,Values=true" \
      "Name=tag:role,Values=load-generator" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId | [0]" \
    --output text
}

get_load_balancer_dns_name() {
  local load_balancer_arn

  load_balancer_arn=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=asg-loadbalancer,Values=true Key=role,Values=loadbalancer \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --query "ResourceTagMappingList[0].ResourceARN" \
    --output text)

  if [[ -z "$load_balancer_arn" || "$load_balancer_arn" == "None" ]]; then
    echo "No load balancer found with tags asg-loadbalancer=true and role=loadbalancer." >&2
    exit 1
  fi

  aws elbv2 describe-load-balancers \
    --load-balancer-arns "$load_balancer_arn" \
    --query "LoadBalancers[0].DNSName" \
    --output text
}

run_request_load() {
  local load_generator_instance_id
  local alb_dns
  local ab_command

  load_generator_instance_id=$(get_load_generator_instance_id)

  if [[ -z "$load_generator_instance_id" ]]; then
    echo "No running EC2 instance found with tags asg-load-generator=true and role=load-generator." >&2
    exit 1
  fi

  alb_dns=$(get_load_balancer_dns_name)
  ab_command="timeout ${DURATION} ab -n ${REQUEST_COUNT} -c ${CONCURRENCY} http://${alb_dns}/ > /dev/null 2>&1 &"

  aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "$load_generator_instance_id" \
    --parameters "commands=[
      \"echo Starting background Apache Bench load for ${DURATION} seconds...\",
      \"${ab_command}\",
      \"echo Apache Bench started in background.\"
    ]" \
    --max-errors "1" \
    --comment "Run Apache Bench in background from load generator instance"
}

if [[ "$RUN_CPU" == true ]]; then
  run_cpu_load
fi

if [[ "$RUN_REQUESTS" == true ]]; then
  run_request_load
fi
