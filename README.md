# Rain

AWS CloudFormation templates managed with the [Rain CLI](https://github.com/aws-cloudformation/rain).

## Directory Structure

```
rain/
  applications/   Jenkins server and agent stacks
  ec2/            Linux instance templates (Ubuntu, Amazon Linux, NGINX)
  iam/            GitHub OIDC provider for keyless CI/CD auth
  kubernetes/     Minikube on Amazon Linux for Kubernetes exploration
  lambda/         Python Lambda functions with Function URLs
  Archive/        Deprecated templates
```

## Templates

### EC2

| Template | Description |
|---|---|
| `ec2/ubuntu-24.04.yml` | Ubuntu 24.04 LTS with Java 21, Git, Python3 |
| `ec2/ubuntu-22.04.yml` | Ubuntu 22.04 LTS with Java 21, Git, Python3 |
| `ec2/amazon-linux-2023.yml` | Amazon Linux 2023 with Java 21, Git, Python3 |
| `ec2/amazon-linux-2023-nginx.yml` | Amazon Linux 2023 with NGINX |

### Lambda

| Template | Description |
|---|---|
| `lambda/lambda-one-function.yml` | Single Python Lambda with public Function URL |
| `lambda/lambda-two-functions.yml` | Staging + Production Lambdas with GitHub OIDC for CI/CD |

### Applications

| Template | Description |
|---|---|
| `applications/jenkins-server.yml` | Jenkins controller with Docker, NGINX reverse proxy |
| `applications/jenkins-agent.yml` | Jenkins build agent with SSH access to the server |

### IAM

| Template | Description |
|---|---|
| `iam/github-oidc-cloudformation-template.yml` | GitHub Actions OIDC provider (one per AWS account) |

### Kubernetes

| Template | Description |
|---|---|
| `kubernetes/minikube.yml` | Amazon Linux 2023 with Minikube, kubectl, and Docker |

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- [Rain CLI](https://github.com/aws-cloudformation/rain)
- Python 3 with `yamllint` (`pip install -r requirements.txt`)
- [cfn-lint](https://github.com/aws-cloudformation/cfn-lint)

## Usage

Deploy a stack:

```bash
make ubuntu24
make nginx
make jenkins
make minikube
make lambda-one
```

Lint and validate all templates:

```bash
make all
```

## License

[MIT](LICENSE)
