# nginx-lua-waf-kit
.PHONY: help setup build test lint clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

setup: ## Install git hooks and dev tooling
	git config core.hooksPath .githooks
	@command -v pre-commit >/dev/null 2>&1 && pre-commit install || true

lint: ## Run all pre-commit checks on the whole tree
	pre-commit run --all-files

build: ## Build the project
	@echo 'nothing to build: pure Lua modules, load them from nginx'

test: ## Run the tests
	lua test/run.lua

clean: ## Remove build artifacts
	@echo "nothing to clean"
