NAME=$(shell date +%s)

help:
	echo "hello"

ubuntu24:
	rain deploy ubuntu-24.04-ec2.yml $(NAME) --yes --detach

amazonlinux2023:
	rain deploy amazonlinux-2023-ec2.yml $(NAME) --yes --detach

jenkins:
	rain deploy jenkins-server.yml jenkins-server-$(NAME) --yes
	rain deploy jenkins-agent.yml jenkins-agent-$(NAME) --yes --params JenkinsStackName=jenkins-server-$(NAME)



