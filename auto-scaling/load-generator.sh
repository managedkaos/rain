#!/usr/bin/env bash
set -euo pipefail

DURATION=300
RUN_CPU=false
RUN_REQUESTS=false
REQUEST_COUNT=1000000
CONCURRENCY=200
COMMAND_LABELS=()
COMMAND_IDS=()

log_step() {
  printf -- "- %s\n" "$*" >&2
}

usage() {
  cat <<USAGE
Usage: $0 [--duration SECONDS] [--cpu] [--requests [COUNT]] [--concurrency COUNT]

Options:
  --duration SECONDS    Amount of time to sustain load. Defaults to 300.
  --cpu                 Generate CPU load on running instances tagged role=webserver.
  --requests [COUNT]    Generate request load from the load generator instance (adds
                       temporary traffic on top of the baseline ab-load.service on that
                       instance). Defaults to 1000000.
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

record_command_id() {
  local label=$1
  local command_id=$2

  if [[ -z "$command_id" || "$command_id" == "None" ]]; then
    echo "Failed to capture SSM command ID for $label." >&2
    exit 1
  fi

  COMMAND_LABELS+=("$label")
  COMMAND_IDS+=("$command_id")
}

print_command_summary() {
  local index

  if [[ ${#COMMAND_IDS[@]} -eq 0 ]]; then
    return
  fi

  printf "\nCommand summary:\n"
  for index in "${!COMMAND_IDS[@]}"; do
    log_step "${COMMAND_LABELS[$index]} ID: ${COMMAND_IDS[$index]}"
  done

  printf "\nUse the following commands to check status:\n"
  for index in "${!COMMAND_IDS[@]}"; do
    log_step "${COMMAND_LABELS[$index]}"
    printf "\naws ssm list-command-invocations --command-id %q --details --query 'CommandInvocations[].{InstanceId:InstanceId,Status:Status,StatusDetails:StatusDetails}'\n\n" "${COMMAND_IDS[$index]}"
  done

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
  local instance_id
  local ssm_status_output
  local ping_status
  local association_status
  local command_id
  local -a instance_ids
  local -a ready_instance_ids=()

  log_step "Finding running webserver instances for CPU load ..."
  instance_ids_output=$(aws ec2 describe-instances \
    --filters "Name=tag:role,Values=webserver" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)
  read -r -a instance_ids <<< "$instance_ids_output"

  if [[ ${#instance_ids[@]} -eq 0 ]]; then
    echo "No running EC2 instances found with tag role=webserver." >&2
    exit 1
  fi

  log_step "Found ${#instance_ids[@]} webserver instance(s): ${instance_ids[*]}"
  log_step "Checking SSM availability for CPU target instances ..."

  for instance_id in "${instance_ids[@]}"; do
    ping_status_output=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=${instance_id}" \
      --query "InstanceInformationList[0].PingStatus" \
      --output text)

    ping_status=${ping_status_output:-None}

    if [[ "$ping_status" == "Online" ]]; then
      log_step "Instance $instance_id is SSM ready: PingStatus=$ping_status"
      ready_instance_ids+=("$instance_id")
    else
      log_step "Skipping instance $instance_id: PingStatus=$ping_status"
    fi
  done

  if [[ ${#ready_instance_ids[@]} -eq 0 ]]; then
    echo "No CPU target instances are SSM ready with PingStatus=Online." >&2
    exit 1
  fi

  log_step "Using ${#ready_instance_ids[@]} SSM-ready webserver instance(s): ${ready_instance_ids[*]}"
  log_step "Building CPU load command for ${DURATION} seconds..."
  log_step "Sending CPU load command with SSM..."
  command_id=$(aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "${ready_instance_ids[@]}" \
    --parameters "commands=[
      \"echo Starting background stress test for ${DURATION} seconds...\",
      \"nohup stress-ng --cpu 0 -l 85 --vm 1 --timeout ${DURATION}s --metrics-brief >> /tmp/stress-ng.log 2>&1 &\",
      \"echo stress-ng started in background. Check /tmp/stress-ng.log for output.\"
    ]" \
    --max-errors "1" \
    --comment "Run stress-ng in background on ASG webservers" \
    --query "Command.CommandId" \
    --output text)

  record_command_id "CPU load" "$command_id"
  log_step "CPU load command sent. Command ID: $command_id"
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
  # Baseline HTTP load runs continuously via ab-load.service on the load generator; this SSM
  # run adds a bounded spike (timeout … ab …) on top of that service.
  local load_generator_instance_id
  local alb_dns
  local ab_command
  local command_id

  log_step "Finding running load generator instance..."
  load_generator_instance_id=$(get_load_generator_instance_id)

  if [[ -z "$load_generator_instance_id" || "$load_generator_instance_id" == "None" ]]; then
    echo "No running EC2 instance found with tags asg-load-generator=true and role=load-generator." >&2
    exit 1
  fi

  log_step "Found load generator instance: $load_generator_instance_id"
  log_step "Finding load balancer DNS name from tags..."
  alb_dns=$(get_load_balancer_dns_name)
  log_step "Found load balancer DNS name: $alb_dns"

  log_step "Building Apache Bench command for ${DURATION} seconds, ${REQUEST_COUNT} requests, and concurrency ${CONCURRENCY}..."
  ab_command="timeout ${DURATION} ab -n ${REQUEST_COUNT} -c ${CONCURRENCY} http://${alb_dns}/ > /dev/null 2>&1 &"
  log_step "Apache Bench command: $ab_command"

  log_step "Sending request load command with SSM..."
  command_id=$(aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids "$load_generator_instance_id" \
    --parameters "commands=[
      \"echo Starting background Apache Bench load for ${DURATION} seconds...\",
      \"${ab_command}\",
      \"echo Apache Bench started in background.\"
    ]" \
    --max-errors "1" \
    --comment "Run Apache Bench in background from load generator instance" \
    --query "Command.CommandId" \
    --output text)

  record_command_id "Request load" "$command_id"
  log_step "Request load command sent. Command ID: $command_id"
}

log_step "Load generator configuration: duration=${DURATION}s, cpu=${RUN_CPU}, requests=${RUN_REQUESTS}, request_count=${REQUEST_COUNT}, concurrency=${CONCURRENCY}"

if [[ "$RUN_CPU" == true ]]; then
  run_cpu_load
fi

if [[ "$RUN_REQUESTS" == true ]]; then
  run_request_load
fi

print_command_summary
