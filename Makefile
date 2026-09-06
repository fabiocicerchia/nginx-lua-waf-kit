# nginx-lua-waf-kit
#
# Every verb this repository exposes lives here; `make` on its own prints them.
# FC-GEN-057: the same eight verbs in every repo, each either wired or a
# declared no-op that says why. None of them exit 0 quietly.

.DEFAULT_GOAL := help

.PHONY: help setup install build test lint run format analyze clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

setup: ## Install the pre-commit hook
	pre-commit install

lint: ## Run the whole gate — every hook, every file
	pre-commit run --all-files

test: ## Run the tests
	lua test/run.lua

analyze: ## Lint the Lua with the rules in .luacheckrc
	@command -v luacheck >/dev/null 2>&1 || { \
		echo "analyze needs luacheck: luarocks install luacheck" >&2; \
		exit 69; }
	luacheck .

# --- Declared no-ops (FC-GEN-058) ---
# These exit 0 and say why. They are listed under "Not applicable" in the README.

build: ## Not applicable — nothing is compiled
	@echo "Nothing to build: pure Lua modules, loaded from nginx at request time."
	@echo "See README > Not applicable."

install: ## Not applicable — nginx loads these from wherever you put them
	@echo "Nothing to install: point lua_package_path at this checkout, or copy"
	@echo "the modules next to your nginx config. See README > Not applicable."

run: ## Not applicable — a WAF module runs inside nginx, not on its own
	@echo "Nothing to run: these modules are called by nginx per request."
	@echo "See README > Not applicable."

format: ## Rewrite what the gate can fix: whitespace, line endings, final newline
	@# A fixing hook exits 1 when it rewrites a file. That is this target doing
	@# its job, not failing, so the exits are ignored — make still prints what
	@# each hook said.
	-pre-commit run --all-files trailing-whitespace
	-pre-commit run --all-files end-of-file-fixer
	-pre-commit run --all-files mixed-line-ending

clean: ## Nothing is built, so nothing accumulates
	@echo "nothing to clean"
