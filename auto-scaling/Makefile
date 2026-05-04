DURATION=600
REQUESTS=10000000
CONCURRENCY=1000

help: ## Display this help message
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

cpu-spike: ## Create CPU spike for the specified duration
	./load-generator.sh --duration $(DURATION) --cpu


request-spike: ## Create HTTP request spike for the specified duration
	./load-generator.sh --duration $(DURATION) \
		--requests $(REQUESTS) \
		--concurrency $(CONCURRENCY)

.PHONY: help cpu-spike request-spike
