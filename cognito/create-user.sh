#!/bin/bash

STACK_NAME="${1}"
EMAIL="${2}"

if [[ -z "$STACK_NAME" || -z "$EMAIL" ]]; then
  echo "Error: All arguments are required and must not be empty."
  echo "Usage: $0 <STACK_NAME> <EMAIL>"
  exit 1
fi

TEMP_PASSWORD=$(/bin/dd if=/dev/urandom count=1 2> /dev/null | /usr/bin/uuencode -m - | /usr/bin/sed -ne 2p | /usr/bin/cut -c-12)

printf "\n#    Stack Name: ${STACK_NAME}\n"
printf "#     User Name: ${EMAIL}\n"
printf "# Temp Password: ${TEMP_PASSWORD}\n\n"

aws cognito-idp admin-create-user \
  --user-pool-id "$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text)" \
  --username ${EMAIL} \
  --user-attributes Name=email,Value=${EMAIL} Name=email_verified,Value=true \
  --temporary-password "${TEMP_PASSWORD}" || exit 1

URL=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" --output text)

printf "\nConnect to the application URL and login with the username and temp password...\n"
printf "\nApplication URL: ${URL}\n\n"
