# Session Manager Preferences

CloudFormation template for configuring AWS SSM Session Manager preferences including idle timeout, S3 session logging, and CloudWatch logging.

## Deployment

```bash
rain deploy session-manager-preferences.yml session-manager-preferences --region us-west-2
```

## Troubleshooting

### `AWS::EarlyValidation::ResourceExistenceCheck` failure

This error means the `SSM-SessionManagerRunShell` document already exists in the target account/region (e.g., created via the Session Manager console preferences).

**Get detailed failure info:**

```bash
aws cloudformation describe-stack-events --stack-name session-manager-preferences --region us-west-2
```

**Confirm the document exists:**

```bash
aws ssm get-document --name SSM-SessionManagerRunShell --region us-west-2
```

**Resolution options:**

1. Delete the existing document, then redeploy:

   ```bash
   aws ssm delete-document --name SSM-SessionManagerRunShell --region us-west-2
   ```

2. Import the existing resource into CloudFormation so the stack adopts it:

   ```bash
   # Create a resource import file
   cat > import-resources.json <<'EOF'
   [
     {
       "ResourceType": "AWS::SSM::Document",
       "LogicalResourceId": "SSMSessionPreferences",
       "ResourceIdentifier": {
         "Name": "SSM-SessionManagerRunShell"
       }
     }
   ]
   EOF

   # Create the stack using import (stack must not already exist)
   aws cloudformation create-change-set \
     --stack-name session-manager-preferences \
     --change-set-name import-ssm-document \
     --change-set-type IMPORT \
     --resources-to-import file://import-resources.json \
     --template-body file://session-manager-preferences.yml \
     --region us-west-2

   # Wait for the change set to be created
   aws cloudformation describe-change-set \
     --stack-name session-manager-preferences \
     --change-set-name import-ssm-document \
     --region us-west-2

   # Execute the change set to complete the import
   aws cloudformation execute-change-set \
     --stack-name session-manager-preferences \
     --change-set-name import-ssm-document \
     --region us-west-2
   ```

   After the import completes, the stack owns the document and subsequent `rain deploy` updates will work normally. Note that only the SSM document needs to be imported — the S3 bucket and CloudWatch log group are new resources that CloudFormation will create during the import.

### `ROLLBACK_COMPLETE` state

If a prior deployment failed and left the stack in `ROLLBACK_COMPLETE`, delete it before redeploying:

```bash
rain rm session-manager-preferences --region us-west-2
```

## Design Decisions

### CloudWatch log encryption disabled

`cloudWatchEncryptionEnabled` is set to `false` because CloudWatch Logs only supports customer-managed KMS keys for encryption (no AWS-managed or AWS-owned key option). A customer-managed key adds ~$1/month per region and operational overhead. Since session logs are still protected by IAM access controls and the S3 copy retains AES256 encryption at rest, the trade-off favors cost savings. If a KMS key is later required for compliance, add a `AWS::KMS::Key` resource and associate it with the log group via `KmsKeyId`.

## Notes

- The `SSM-SessionManagerRunShell` document is regional. Deploy to each region where Session Manager preferences are needed.
- The `AWS-` prefix is reserved for AWS-owned documents and cannot be used for customer-managed resources.
