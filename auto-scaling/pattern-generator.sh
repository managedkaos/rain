#!/usr/bin/env bash
set -euo pipefail

TOTAL_DURATION=900
INTERVAL=60
RUN_OVER_SCALING=false
RUN_UNDER_SCALING=false
RUN_OSCILLATION=false
ASG_NAME=""
START_CAPACITY=""
MIN_CAPACITY=""
MAX_CAPACITY=""
RESET_ONLY=false
ACTION_LOG=()

log_step() {
  printf -- '- %s\n' "$*" >&2
}

usage() {
  cat >&2 <<'USAGE'
Usage: ./pattern-generator.sh [pattern] [options]

Patterns:
  --over-scaling           Set desired capacity through a 15-minute over-scaling pattern.
  --under-scaling          Set desired capacity through a 15-minute under-scaling pattern.
  --oscillation            Set desired capacity through a 15-minute oscillation pattern.

Options:
  --asg-name NAME          Auto Scaling group name. Defaults to the first ASG in the active region.
  --start-capacity COUNT   Starting desired capacity before pattern begins. Defaults to current desired capacity.
  --min-capacity COUNT     Override the ASG minimum size for pattern calculations.
  --max-capacity COUNT     Override the ASG maximum size for pattern calculations.
  --total-duration SECONDS Total pattern duration. Defaults to 900 seconds (15 minutes).
  --interval SECONDS       Seconds between desired-capacity changes. Defaults to 60.
  --reset                  Set desired capacity to the starting capacity and exit.
  -h, --help               Show this help.

Examples:
  ./pattern-generator.sh --over-scaling
  ./pattern-generator.sh --under-scaling --asg-name my-demo-asg
  ./pattern-generator.sh --oscillation --asg-name my-demo-asg --start-capacity 2
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

require_non_negative_integer() {
  local key=$1
  local value=$2
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "$key must be a non-negative integer." >&2
    exit 1
  fi
}

get_default_asg_name() {
  aws autoscaling describe-auto-scaling-groups \
    --query 'AutoScalingGroups[0].AutoScalingGroupName' \
    --output text
}

get_asg_value() {
  local query=$1
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "$query" \
    --output text
}

clamp_capacity() {
  local requested=$1
  local clamped=$requested

  if (( clamped < MIN_CAPACITY )); then
    clamped=$MIN_CAPACITY
  fi
  if (( clamped > MAX_CAPACITY )); then
    clamped=$MAX_CAPACITY
  fi

  printf '%s\n' "$clamped"
}

set_desired_capacity_step() {
  local label=$1
  local desired=$2

  log_step "${label}: setting desired capacity to ${desired} for Auto Scaling group ${ASG_NAME}."
  aws autoscaling set-desired-capacity \
    --auto-scaling-group-name "$ASG_NAME" \
    --desired-capacity "$desired" \
    --no-honor-cooldown

  ACTION_LOG+=("${label} => desired capacity ${desired}")
}

print_action_summary() {
  local action

  if [[ ${#ACTION_LOG[@]} -eq 0 ]]; then
    return
  fi

  printf '\nAction summary:\n\n'
  for action in "${ACTION_LOG[@]}"; do
    log_step "$action"
  done

  printf '\nCheck scaling activity with:\n\n'
  printf "aws autoscaling describe-scaling-activities --auto-scaling-group-name %q --query 'Activities[].[StartTime,Description,StatusCode,Cause]' --output table\n" "$ASG_NAME"
}

build_over_scaling_pattern() {
  local start=$1
  local s1 s2 s3 s4
  s1=$(clamp_capacity "$start")
  s2=$(clamp_capacity $((start + 2)))
  s3=$(clamp_capacity $((start + 3)))
  s4=$(clamp_capacity "$MAX_CAPACITY")

  printf '%s\n' \
    "$s1" "$s2" "$s3" "$s4" "$s4" \
    "$s4" "$s3" "$s3" "$s2" "$s2" \
    "$s2" "$s2" "$s2" "$s2" "$s2"
}

build_under_scaling_pattern() {
  local start=$1
  local s1 s2 s3
  s1=$(clamp_capacity "$start")
  s2=$(clamp_capacity $((start + 1)))
  s3=$(clamp_capacity $((MAX_CAPACITY - 1)))

  printf '%s\n' \
    "$s1" "$s1" "$s1" "$s1" "$s1" \
    "$s1" "$s1" "$s1" "$s2" "$s2" \
    "$s3" "$s3" "$MAX_CAPACITY" "$MAX_CAPACITY" "$MAX_CAPACITY"
}

build_oscillation_pattern() {
  local start=$1
  local mid low high
  mid=$(clamp_capacity "$start")
  low=$(clamp_capacity "$MIN_CAPACITY")
  high=$(clamp_capacity "$MAX_CAPACITY")

  printf '%s\n' \
    "$mid" "$high" "$low" "$high" "$low" \
    "$high" "$low" "$high" "$low" "$high" \
    "$low" "$high" "$low" "$mid" "$mid"
}

run_pattern() {
  local pattern_name=$1
  shift
  local -a capacities=("$@")
  local index desired

  for index in "${!capacities[@]}"; do
    desired=${capacities[$index]}
    set_desired_capacity_step "${pattern_name} minute $((index + 1))" "$desired"
    if (( index < ${#capacities[@]} - 1 )); then
      sleep "$INTERVAL"
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --over-scaling)
      RUN_OVER_SCALING=true
      shift
      ;;
    --under-scaling)
      RUN_UNDER_SCALING=true
      shift
      ;;
    --oscillation)
      RUN_OSCILLATION=true
      shift
      ;;
    --asg-name)
      ASG_NAME=$2
      shift 2
      ;;
    --start-capacity)
      START_CAPACITY=$2
      shift 2
      ;;
    --min-capacity)
      MIN_CAPACITY=$2
      shift 2
      ;;
    --max-capacity)
      MAX_CAPACITY=$2
      shift 2
      ;;
    --total-duration)
      TOTAL_DURATION=$2
      shift 2
      ;;
    --interval)
      INTERVAL=$2
      shift 2
      ;;
    --reset)
      RESET_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

pattern_count=0
[[ "$RUN_OVER_SCALING" == true ]] && ((pattern_count+=1))
[[ "$RUN_UNDER_SCALING" == true ]] && ((pattern_count+=1))
[[ "$RUN_OSCILLATION" == true ]] && ((pattern_count+=1))
if [[ $pattern_count -ne 1 && "$RESET_ONLY" == false ]]; then
  echo 'Select exactly one of --over-scaling, --under-scaling, or --oscillation.' >&2
  usage
  exit 1
fi

require_positive_integer --total-duration "$TOTAL_DURATION"
require_positive_integer --interval "$INTERVAL"
if (( TOTAL_DURATION % INTERVAL != 0 )); then
  echo '--total-duration must be evenly divisible by --interval.' >&2
  exit 1
fi
if (( TOTAL_DURATION / INTERVAL != 15 )); then
  echo 'This script is designed for 15 points across 15 minutes. Use --total-duration 900 and --interval 60.' >&2
  exit 1
fi

if [[ -n "$START_CAPACITY" ]]; then
  require_positive_integer --start-capacity "$START_CAPACITY"
fi
if [[ -n "$MIN_CAPACITY" ]]; then
  require_non_negative_integer --min-capacity "$MIN_CAPACITY"
fi
if [[ -n "$MAX_CAPACITY" ]]; then
  require_positive_integer --max-capacity "$MAX_CAPACITY"
fi

if [[ -z "$ASG_NAME" ]]; then
  ASG_NAME=$(get_default_asg_name)
fi
if [[ -z "$ASG_NAME" || "$ASG_NAME" == 'None' ]]; then
  echo 'No Auto Scaling groups found in the active region.' >&2
  exit 1
fi

CURRENT_DESIRED=$(get_asg_value 'AutoScalingGroups[0].DesiredCapacity')
ASG_MIN=$(get_asg_value 'AutoScalingGroups[0].MinSize')
ASG_MAX=$(get_asg_value 'AutoScalingGroups[0].MaxSize')

if [[ -z "$MIN_CAPACITY" ]]; then
  MIN_CAPACITY=$ASG_MIN
fi
if [[ -z "$MAX_CAPACITY" ]]; then
  MAX_CAPACITY=$ASG_MAX
fi
if [[ -z "$START_CAPACITY" ]]; then
  START_CAPACITY=$CURRENT_DESIRED
fi

if (( MIN_CAPACITY > MAX_CAPACITY )); then
  echo '--min-capacity cannot be greater than --max-capacity.' >&2
  exit 1
fi
if (( START_CAPACITY < MIN_CAPACITY || START_CAPACITY > MAX_CAPACITY )); then
  echo '--start-capacity must be within the min/max capacity range.' >&2
  exit 1
fi

if [[ "$RESET_ONLY" == true ]]; then
  set_desired_capacity_step 'Reset desired capacity' "$START_CAPACITY"
  print_action_summary
  exit 0
fi

log_step "Configuration: asg=${ASG_NAME}, start=${START_CAPACITY}, min=${MIN_CAPACITY}, max=${MAX_CAPACITY}, total_duration=${TOTAL_DURATION}s, interval=${INTERVAL}s"

mapfile -t capacities < <(
  if [[ "$RUN_OVER_SCALING" == true ]]; then
    build_over_scaling_pattern "$START_CAPACITY"
  elif [[ "$RUN_UNDER_SCALING" == true ]]; then
    build_under_scaling_pattern "$START_CAPACITY"
  else
    build_oscillation_pattern "$START_CAPACITY"
  fi
)

if [[ "$RUN_OVER_SCALING" == true ]]; then
  run_pattern 'Over-scaling' "${capacities[@]}"
elif [[ "$RUN_UNDER_SCALING" == true ]]; then
  run_pattern 'Under-scaling' "${capacities[@]}"
else
  run_pattern 'Oscillation' "${capacities[@]}"
fi

print_action_summary
