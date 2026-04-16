#!/bin/bash
set -e

if [ ${#1} -gt 13 ]; then
  echo "ERROR: NAME must be 13 characters or less. Length = ${#1}: '${1}'"
  exit 1
fi

STACK_NAME="${1}"
TEMPLATE="cognito/cognito-lambda.yml"

echo "==> Pass 1: Creating stack ${STACK_NAME} ..."
rain deploy "${TEMPLATE}" "${STACK_NAME}" --yes --params AppName="${NAME}"

echo "==> Fetching Function URL ..."
APP_URL=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" --output text)

echo "==> Pass 2: Updating stack with Function URL = ${APP_URL} ..."
rain deploy "${TEMPLATE}" "${STACK_NAME}" --yes --params "AppName=${NAME},AppUrl=${APP_URL}"

echo "==> Done."

aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[*].Outputs[*]" --output json
