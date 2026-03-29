NAME=$(shell date +%s)
PREFIX=server-
TEMPLATES=$(shell find ec2 lambda applications iam kubernetes -name '*.yml' 2>/dev/null)
# GNU Make uses SHELL=/bin/sh with .SHELLFLAGS=-c (`make -p | grep SHELL`). Loop
# recipes use `set -e` so the first failing command stops the recipe.

help:
	echo "hello"

get-stacks:
	rain ls

global-get-stacks:
	rain ls --all

all: lint validate

lint: yaml-lint cfn-lint

yaml-lint:
	@echo && echo "# YAML lint ..."
	@set -e; for template in $(TEMPLATES); do \
		echo "Linting $$template"; \
		yamllint $$template; \
	done

cfn-lint:
	@echo && echo "# CloudFormation lint ..."
	@set -e; for template in $(TEMPLATES); do \
		echo "Linting $$template"; \
		cfn-lint --template $$template --non-zero-exit-code error; \
	done

validate:
	@echo && echo "# Validating CloudFormation templates ..."
	@set -e; for template in $(TEMPLATES); do \
		echo "Validating $$template"; \
		aws cloudformation validate-template --template-body file://$$template > /dev/null; \
	done

lambda-one:
	rain deploy lambda/lambda-one-function.yml lambda-$(NAME) --yes --detach

lambda-two:
	rain deploy lambda/lambda-two-functions.yml lambda-$(NAME) --yes --detach

ubuntu24:
	rain deploy ec2/ubuntu-24.04.yml $(PREFIX)$(NAME) --yes --detach

amazonlinux2023:
	rain deploy ec2/amazon-linux-2023.yml $(PREFIX)$(NAME) --yes --detach

nginx:
	rain deploy ec2/amazon-linux-2023-nginx.yml nginx-$(NAME) --yes --detach

jenkins:
	rain deploy applications/jenkins-server.yml jenkins-server-$(NAME) --yes
	rain deploy applications/jenkins-agent.yml jenkins-agent-$(NAME) --yes --params JenkinsStackName=jenkins-server-$(NAME)

minikube:
	rain deploy kubernetes/minikube.yml minikube-$(NAME) --yes --detach

kind:
	rain deploy kubernetes/kind.yml kind-$(NAME) --yes --detach

k3s:
	rain deploy kubernetes/k3s.yml k3s-$(NAME) --yes --detach

clean:
	@echo "#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#"
	@echo "# WARNING: This will remove all CloudFormation stacks and associated resources."
	@echo "# WARNING: This action is irreversible."
	@echo "#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#"
	@echo
	@echo "Type CTRL+C to abort."
	@echo
	@read -p "Type the current date in YYYY-MM-DD format to confirm: " input_date; \
	if [ "$$input_date" = "$(shell date +%Y-%m-%d)" ]; then \
		echo "Date confirmed. Proceeding with removal..."; \
		echo "Fetching all CloudFormation stacks..."; \
	else \
		echo "Date confirmation failed. Aborting..."; \
	fi

.PHONY: help all lint validate ubuntu24 amazonlinux2023 nginx jenkins lambda-one lambda-two minikube kind k3s
