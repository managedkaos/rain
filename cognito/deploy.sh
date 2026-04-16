#!/bin/bash
set -e

NAME="${1}"
STACK_NAME="${NAME}"
TEMPLATE="cognito/cognito-lambda.yml"

echo "==> Pass 1: Creating stack ${STACK_NAME} ..."
rain deploy "${TEMPLATE}" "${STACK_NAME}" --yes --params "AppName=${NAME}"

echo "==> Fetching Function URL ..."
APP_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" \
  --output text | sed 's:/$::')

echo "==> Pass 2: Updating stack with AppUrl=${APP_URL} ..."
rain deploy "${TEMPLATE}" "${STACK_NAME}" --yes --params "AppName=${NAME},AppUrl=${APP_URL}"

echo "==> Done. Application URL: ${APP_URL}"
