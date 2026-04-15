# Lambda Auth

A single-page web application deployed as an AWS Lambda function with Amazon Cognito authentication, defined entirely in a CloudFormation template.

## Notes on Omitting API Gateway

The template intentionally omits API Gateway. It uses a Lambda Function URL (AWS::Lambda::Url) instead, which gives the Lambda function its own HTTPS endpoint directly.

How it works:

  - Lambda Function URLs provide a dedicated https://<url-id>.lambda-url.<region>.on.aws endpoint
  - Incoming HTTP requests are passed to the handler in the same event format as API Gateway HTTP API (payload format v2.0) — that's why rawPath, cookies, and queryStringParameters all work as-is in the handler
  - The routing (/login, /authorize, /logout, /) is handled by branching on rawPath inside the function code itself

What you gain by skipping API Gateway:

  - Fewer resources to manage (no AWS::ApiGatewayV2::Api, stage, integration, routes)
  - No API Gateway cost — Lambda Function URLs are free; you only pay for Lambda invocations
  - Simpler template and faster deploys

What you give up:

  - Custom domain names (would need CloudFront in front)
  - Built-in rate limiting, throttling, and usage plans
  - WAF integration (requires CloudFront as an intermediary)
  - Request/response transformation
  - API key management
  - Routing across multiple Lambda functions

For a simple single-function app like this one, a Function URL is sufficient. If you later need custom domains, rate limiting, or WAF, the typical path is to add a CloudFront distribution in front of the Function URL rather than switching to API Gateway.

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
