#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <stack-name> [VERSION] [BUILD_NUMBER]"
  echo
  echo "Deploys index.py and template.html to the Lambda function managed by"
  echo "the given CloudFormation stack, preserving Cognito environment variables"
  echo "set by the stack (CLIENT_ID, COGNITO_DOMAIN, REDIRECT_URI, SECRET_KEY)."
  exit 1
fi

STACK_NAME="$1"
VERSION="${2:-0}"
BUILD_NUMBER="${3:-0}"

echo "==> Fetching function name from stack ${STACK_NAME} ..."
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionName'].OutputValue" \
  --output text)

if [ -z "${FUNCTION_NAME}" ] || [ "${FUNCTION_NAME}" = "None" ]; then
  echo "ERROR: Could not find FunctionName output in stack '${STACK_NAME}'."
  exit 1
fi

echo "==> Function: ${FUNCTION_NAME}"

echo "==> Fetching current environment variables ..."
CURRENT_ENV=$(aws lambda get-function-configuration \
  --function-name "${FUNCTION_NAME}" \
  --query "Environment.Variables" \
  --output json)

MERGED_ENV=$(echo "${CURRENT_ENV}" | python3 -c "
import sys, json
raw = json.load(sys.stdin)
env = raw if isinstance(raw, dict) else {}
env['VERSION'] = '${VERSION}'
env['BUILD_NUMBER'] = '${BUILD_NUMBER}'
env['PLATFORM'] = 'deploy.sh'
print(json.dumps(env))
")

if echo "${MERGED_ENV}" | python3 -c "import sys,json; env=json.load(sys.stdin); missing=[k for k in ('CLIENT_ID','COGNITO_DOMAIN','REDIRECT_URI','SECRET_KEY') if k not in env]; sys.exit(0 if not missing else 1)" 2>/dev/null; then
  :
else
  echo "ERROR: Cognito environment variables (CLIENT_ID, COGNITO_DOMAIN, REDIRECT_URI, SECRET_KEY)"
  echo "       are missing from the Lambda configuration. This usually means a previous deploy"
  echo "       wiped them. Re-run the CloudFormation stack deploy first to restore them:"
  echo "         cd .. && ./deploy.sh python-lambda ${STACK_NAME}"
  exit 1
fi

echo "==> Building lambda.zip ..."
zip -j lambda.zip index.py template.html

echo "==> Updating function configuration ..."
aws lambda wait function-active \
  --function-name="${FUNCTION_NAME}"

aws lambda update-function-configuration \
  --function-name="${FUNCTION_NAME}" \
  --environment "{\"Variables\": ${MERGED_ENV}}"

aws lambda wait function-updated \
  --function-name="${FUNCTION_NAME}"

echo "==> Updating function code ..."
aws lambda update-function-code \
  --function-name="${FUNCTION_NAME}" \
  --zip-file=fileb://lambda.zip

aws lambda wait function-updated \
  --function-name="${FUNCTION_NAME}"

echo "==> Done."

FUNCTION_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" \
  --output text)

echo "==> ${FUNCTION_URL}"
