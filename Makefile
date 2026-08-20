# openshell-sandbox

IMAGE_NAME ?= openshell-sandbox
IMAGE_TAG ?= latest
IMAGE_REF = $(IMAGE_NAME):$(IMAGE_TAG)
CONTAINER_TOOL ?= podman
SHELLCHECK ?= shellcheck

# scode has no extension; everything else is *.sh. config/bashrc and
# bin/claude.env are sourced fragments, not scripts, and are left out.
SHELL_SOURCES ?= $(wildcard bin/*.sh fetchsvc/*.sh scripts/*.sh scripts/explore/*.sh tests/*.sh) scripts/scode
TEST_SCRIPTS ?= $(wildcard tests/test-*.sh)

.PHONY: build build-force check clean help test-lint test-unit

check: test-lint test-unit  ## Run the full quality gate

build:  ## Build the sandbox container image
	$(CONTAINER_TOOL) build -t $(IMAGE_REF) -f Containerfile .

# `npm install -g @anthropic-ai/claude-code` pins nothing, so its layer caches
# on the Containerfile text — which never changes when a new Claude Code is
# published. A normal `make build` then reuses the layer and ships the old CLI.
# --no-cache is the whole point of this target; --pull picks up a newer base at
# the same time. Rebuilds apt and pip too, so it is slow by design.
build-force: clean  ## Rebuild the image from scratch (no cache, fresh base)
	$(CONTAINER_TOOL) build --no-cache --pull -t $(IMAGE_REF) -f Containerfile .

clean:  ## Remove built image
	$(CONTAINER_TOOL) rmi $(IMAGE_REF) 2>/dev/null || true

# Only warnings and errors gate. The info/style notes (SC2016 in test fixtures,
# SC1091 for sourced files that are gitignored or resolved at runtime) are
# noise here; run `make test-lint SHELLCHECK_SEVERITY=style` to see them.
SHELLCHECK_SEVERITY ?= warning

test-lint:  ## Lint shell sources with shellcheck
	@command -v $(SHELLCHECK) >/dev/null 2>&1 || { \
	    echo "error: $(SHELLCHECK) not found — install it or set SHELLCHECK=<path>" >&2; \
	    exit 1; \
	}
	$(SHELLCHECK) --severity=$(SHELLCHECK_SEVERITY) $(SHELL_SOURCES)

test-unit:  ## Run the shell self-checks in tests/
	@for t in $(TEST_SCRIPTS); do \
	    echo "==> $$t"; \
	    bash "$$t" || exit 1; \
	done

help:  ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := check
