#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <template-dir> <stack-name>"
  exit 1
fi

TEMPLATE="${1}/${1}.yml"

if [ ! -d "$1" ] || [ ! -f "${TEMPLATE}" ]; then
  echo "ERROR: '${1}' is not a directory or '${TEMPLATE}' does not exist."
  exit 1
fi

if [ ${#2} -gt 13 ]; then
  echo "ERROR: NAME must be 13 characters or less. Length = ${#2}: '${2}'"
  exit 1
fi

STACK_NAME="${2}"

echo "==> Pass 1: Creating stack ${STACK_NAME} ..."
rain deploy "${TEMPLATE}" "${STACK_NAME}" --yes --params AppName="${STACK_NAME}"

echo "==> Fetching Function URL ..."
APP_URL=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" --output text)

echo "==> Pass 2: Updating stack with Function URL = ${APP_URL} ..."
rain deploy "${TEMPLATE}" "${STACK_NAME}" --yes --params "AppName=${STACK_NAME},AppUrl=${APP_URL}"

echo "==> Done."

aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[*].Outputs[*]" --output json
