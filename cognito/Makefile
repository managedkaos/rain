name-length-check:
	@if [ $$(printf '%s' '$(NAME)' | wc -c) -gt 13 ]; then \
		echo "ERROR: NAME must be 13 characters or less. Length = $$(printf '%s' '$(NAME)' | wc -c | tr -d ' '): '$(NAME)'"; \
		printf '\nPlease set NAME to a shorter value (e.g., NAME=shortname) and try again.\n\n'; \
		exit 1; \
	fi

cognito: name-length-check
	@cognito/deploy.sh $(NAME)
