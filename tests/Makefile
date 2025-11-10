.PHONY: help all smoke integration security clean

# Load version configuration
include ../versions.env

# Test configuration
IMAGE ?= cmooreio/arpwatch:latest

help: ## Display this help message
	@echo "Arpwatch Test Suite"
	@echo ""
	@echo "Current Configuration:"
	@echo "  Image:    $(IMAGE)"
	@echo "  Version:  $(VERSION)"
	@echo ""
	@echo "Available Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: smoke integration security ## Run all test suites

smoke: ## Run smoke tests (basic functionality)
	@echo "Running smoke tests..."
	@./smoke_test.sh

integration: ## Run integration tests
	@echo "Running integration tests..."
	@./integration_test.sh

security: ## Run security tests
	@echo "Running security tests..."
	@./security_test.sh

clean: ## Clean up test artifacts
	@echo "Cleaning up test artifacts..."
	@docker volume ls -q | grep arpwatch-test | xargs -r docker volume rm || true
	@echo "Cleanup complete"
