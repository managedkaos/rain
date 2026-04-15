# Lambda Auth

A single-page web application deployed as an AWS Lambda function with Amazon Cognito authentication, defined entirely in a CloudFormation template.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Permissions to create IAM roles, Lambda functions, and Cognito resources

## Deployment

Deployment is a two-step process. The first deploy creates all resources including the Lambda Function URL. The second deploy feeds that URL back into the Cognito callback configuration.

### Step 1 — Create the stack

```bash
aws cloudformation deploy \
  --template-file lambda-auth.yml \
  --stack-name my-app \
  --capabilities CAPABILITY_NAMED_IAM
```

### Step 2 — Update with the Function URL

```bash
APP_URL=$(aws cloudformation describe-stacks \
  --stack-name my-app \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" \
  --output text | sed 's:/$::')

aws cloudformation deploy \
  --template-file lambda-auth.yml \
  --stack-name my-app \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AppUrl="$APP_URL"
```

## Creating a user

After deployment, create a user in the Cognito User Pool:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$(aws cloudformation describe-stacks \
    --stack-name my-app \
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" \
    --output text)" \
  --username user@example.com \
  --user-attributes Name=email,Value=user@example.com Name=email_verified,Value=true \
  --temporary-password 'TempPass1'
```

The user will be prompted to set a permanent password on first login.

## Accessing the application

Open the Function URL in a browser:

```bash
aws cloudformation describe-stacks \
  --stack-name my-app \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionURL'].OutputValue" \
  --output text
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name my-app
```
