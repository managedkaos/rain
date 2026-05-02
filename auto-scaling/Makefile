DURATION=600
REQUESTS=10000000

help: ## Display this help message
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

cpu: ## Run CPU load test for the specified duration
	./load-generator.sh --duration $(DURATION) --cpu


requests: ## Run HTTP requests load test for the specified duration
	./load-generator.sh --duration $(DURATION) \
		--requests $(REQUESTS) \
		--concurrency 1000 \

.PHONY: help cpu requests
