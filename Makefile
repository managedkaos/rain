NAME=$(shell date +%s)
PREFIX=server-
TEMPLATES=$(shell ls *.yml)

help:
	echo "hello"

all: lint validate

lint:
	@for template in $(TEMPLATES); do \
		echo "Linting $$template..."; \
		cfn-lint -t $$template; \
	done

validate:
	@for template in $(TEMPLATES); do \
		echo "Validating $$template..."; \
		aws cloudformation validate-template --template-body file://$$template > /dev/null; \
	done

ubuntu24:
	rain deploy ubuntu-24.04.yml $(PREFIX)$(NAME) --yes --detach

amazonlinux2023:
	rain deploy amazonlinux-2023.yml $(PREFIX)$(NAME) --yes --detach

nginx:
	rain deploy amazon-linux-2023-nginx.yml nginx-$(NAME) --yes --detach

jenkins:
	rain deploy jenkins-server.yml jenkins-server-$(NAME) --yes
	rain deploy jenkins-agent.yml jenkins-agent-$(NAME) --yes --params JenkinsStackName=jenkins-server-$(NAME)

