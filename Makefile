NAME=$(shell date +%s)
PREFIX=server-
TEMPLATES=$(shell find ec2 lambda applications iam kubernetes cognito -name '*.yml' 2>/dev/null)
# GNU Make uses SHELL=/bin/sh with .SHELLFLAGS=-c (`make -p | grep SHELL`). Loop
# recipes use `set -e` so the first failing command stops the recipe.

help: ## Display this help message
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

requirements: ## Install Python requirements
	pip install --upgrade pip
	pip install --requirement requirements.txt

ls: ## List CloudFormation stacks in the current region
	@rain ls

global-ls: ## List CloudFormation stacks in all regions
	@rain ls --all

all: lint validate ## Run linting and validation

lint: yaml-lint cfn-lint ## Run yaml-lint and cfn-lint

yaml-lint: ## Lint YAML templates
	@echo && echo "# YAML lint ..."
	@set -e; for template in $(TEMPLATES); do \
		echo "Linting $$template"; \
		yamllint $$template; \
	done

cfn-lint: ## Lint CloudFormation templates
	@echo && echo "# CloudFormation lint ..."
	@set -e; for template in $(TEMPLATES); do \
		echo "Linting $$template"; \
		cfn-lint --template $$template --non-zero-exit-code error; \
	done

validate: ## Validate CloudFormation templates using AWS CLI
	@echo && echo "# Validating CloudFormation templates ..."
	@set -e; for template in $(TEMPLATES); do \
		echo "Validating $$template"; \
		aws cloudformation validate-template --template-body file://$$template > /dev/null; \
	done

lambda-one: ## Deploy a one-function Lambda stack
	rain deploy lambda/lambda-one-function.yml lambda-$(NAME) --yes --detach

lambda-two: ## Deploy a two-function Lambda stack
	rain deploy lambda/lambda-two-functions.yml lambda-$(NAME) --yes --detach

ubuntu24: ## Deploy an Ubuntu 24.04 EC2 instance
	rain deploy ec2/ubuntu-24.04.yml $(PREFIX)$(NAME) --yes --detach

amazonlinux2023: ## Deploy an Amazon Linux 2023 EC2 instance
	rain deploy ec2/amazon-linux-2023.yml $(PREFIX)$(NAME) --yes --detach

nginx: ## Deploy an Nginx server on Amazon Linux 2023
	rain deploy ec2/amazon-linux-2023-nginx.yml nginx-$(NAME) --yes --detach

jenkins: ## Deploy Jenkins server and agent stacks
	rain deploy applications/jenkins-server.yml jenkins-server-$(NAME) --yes
	rain deploy applications/jenkins-agent.yml jenkins-agent-$(NAME) --yes --params JenkinsStackName=jenkins-server-$(NAME)

minikube: ## Deploy a Minikube stack
	rain deploy kubernetes/minikube.yml minikube-$(NAME) --yes --detach

kind: ## Deploy a Kind stack
	rain deploy kubernetes/kind.yml kind-$(NAME) --yes --detach

k3s: ## Deploy a K3s stack
	rain deploy kubernetes/k3s.yml k3s-$(NAME) --yes --detach

name-length-check: ## Internal check for Cognito stack name length
	@if [ $$(printf '%s' '$(NAME)' | wc -c) -gt 13 ]; then \
		echo "ERROR: NAME must be 13 characters or less. Length = $$(printf '%s' '$(NAME)' | wc -c | tr -d ' '): '$(NAME)'"; \
		printf '\nPlease set NAME to a shorter value (e.g., NAME=shortname) and try again.\n\n'; \
		exit 1; \
	fi

cognito: name-length-check ## Deploy a Cognito stack
	@cognito/deploy.sh $(STACK) $(NAME)

clean: ## Remove all CloudFormation stacks (with confirmation)
	@stacks=$$(rain ls | awk '{print $$1}' | grep -v aws-sam-cli-managed-default | grep -v CloudFormation | sed -e 's/://'); \
	if [ -z "$$stacks" ]; then \
		echo "No stacks to remove."; \
		exit 0; \
	fi; \
	echo "#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#"; \
	echo "# WARNING: This will remove the following CloudFormation stacks and their associated resources:"; \
	echo "#"; \
	for s in $$stacks; do echo "#   $$s"; done; \
	echo "#"; \
	echo "# This action is irreversible."; \
	echo "#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#"; \
	echo; \
	echo "Type CTRL+C to abort."; \
	echo; \
	read -p "Type the current date in YYYY-MM-DD format to confirm: " input_date; \
	if [ "$$input_date" = "$$(date +%Y-%m-%d)" ]; then \
		echo "Date confirmed. Proceeding with removal..."; \
		for stack in $$stacks; do \
			echo "Removing $$stack ..."; \
			rain rm $$stack --yes --detach; \
		done; \
	else \
		echo "Date confirmation failed. Aborting..."; \
	fi

.PHONY: help requirements ls global-ls all lint yaml-lint cfn-lint validate lambda-one lambda-two ubuntu24 amazonlinux2023 nginx jenkins minikube kind k3s name-length-check cognito clean
