NAME=undefined
VERSION=0
BUILD_NUMBER=0
CODE=$(shell ls *.py)

hello:
	@echo "Here are the targets for this Makefile:"
	@echo "  requirements   - install the project requirements"
	@echo "  lint           - run linters on the code"
	@echo "  black          - run black to format the code"
	@echo "  build          - build the lambda.zip file"
	@echo "  deploy         - deploy the lambda.zip file to AWS"
	@echo "  clean          - remove the lambda.zip file"
	@echo "  all            - clean, lint, black, build, and deploy"
	@echo
	@echo
	@echo "You must set NAME to use the deploy target."
	@echo "NAME must be set to the CloudFormation stack name."
	@echo "For example:"
	@echo
	@echo "  make deploy NAME=pylambda-v1 VERSION=1 BUILD_NUMBER=1"
	@echo
	@echo "Optional deploy variables are:"
	@echo "  VERSION       - the version of the code being deployed (default: 0)"
	@echo "  BUILD_NUMBER  - the build number assigned by the deployment platform (default: 0)"
	@echo

requirements:
	pip install -U pip
	pip install --requirement requirements.txt

check:
	set
	zip --version
	python --version
	pylint --version
	flake8 --version
	aws --version

lint:
	pylint --exit-zero --errors-only --disable=C0301 --disable=C0326 --disable=R,C $(CODE)
	flake8 --exit-zero --ignore=E501,E231 $(CODE)


black:
	black --diff $(CODE)

build:
	zip lambda.zip index.py template.html

deploy:
	aws sts get-caller-identity
	./deploy-function.sh $(NAME) $(VERSION) $(BUILD_NUMBER)

clean:
	rm -vf lambda.zip

all: clean lint black build deploy

.PHONY: lint black build deploy all clean
