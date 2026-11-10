# openshell-sandbox

IMAGE_NAME ?= openshell-sandbox
IMAGE_TAG ?= latest
IMAGE_REF = $(IMAGE_NAME):$(IMAGE_TAG)
WORK_IMAGE_REF = $(IMAGE_NAME)-work:$(IMAGE_TAG)
CONTAINER_TOOL ?= podman
SHELLCHECK ?= shellcheck

# Managed settings are honored by Claude Code only from this system path.
# The sandbox cannot write /etc, so the work image bakes the host's file in.
MANAGED_SETTINGS_SRC ?= /etc/claude-code/managed-settings.json
MANAGED_SETTINGS_STAGE = .tmp-managed-settings.json

# scode has no extension; everything else is *.sh. config/bashrc and
# bin/claude.env are sourced fragments, not scripts, and are left out.
SHELL_SOURCES ?= $(wildcard bin/*.sh fetchsvc/*.sh scripts/*.sh scripts/explore/*.sh tests/*.sh) scripts/scode
TEST_SCRIPTS ?= $(wildcard tests/test-*.sh)

.PHONY: build build-fetcher build-force check clean help stage-managed-settings stage-wrappers test-lint test-unit

check: test-lint test-unit  ## Run the full quality gate

build: build-fetcher stage-wrappers stage-managed-settings  ## Build the sandbox, work, and fetch-service container images
	$(CONTAINER_TOOL) build -t $(IMAGE_REF) -f Containerfile .
	$(CONTAINER_TOOL) build -t $(WORK_IMAGE_REF) -f Containerfile.work \
	    --build-arg BASE_IMAGE=$(IMAGE_REF) .

# Delegates rather than repeating the podman command: fetchsvc.sh owns the
# image name, and `up` refuses to start when that image is missing. Building it
# here is near-free — same base as the sandbox image, one COPY layer on top —
# and the alternative is a build step nothing points at, which is how a missing
# fetch-service image surfaced as podman's short-name/TTY error instead.
build-fetcher:  ## Build the fetch-service container image
	./fetchsvc/fetchsvc.sh build

# `npm install -g @anthropic-ai/claude-code` pins nothing, so its layer caches
# on the Containerfile text — which never changes when a new Claude Code is
# published. A normal `make build` then reuses the layer and ships the old CLI.
# --no-cache is the whole point of this target; --pull picks up a newer base at
# the same time. Rebuilds apt and pip too, so it is slow by design.
build-force: clean stage-wrappers stage-managed-settings  ## Rebuild the images from scratch (no cache, fresh base)
	$(CONTAINER_TOOL) build --no-cache --pull -t $(IMAGE_REF) -f Containerfile .
	$(CONTAINER_TOOL) build --no-cache -t $(WORK_IMAGE_REF) -f Containerfile.work \
	    --build-arg BASE_IMAGE=$(IMAGE_REF) .

# The claude/codex PATH shims come from claude-otel-stack, the one source for
# host and sandbox. Copied into the build context because COPY cannot reach
# outside it; .tmp-* is gitignored. bin/claude's host telemetry block is skipped
# when /sandbox/.env exists, so the sandbox keeps config/bashrc + /sandbox/.env.
OTEL_STACK_BIN ?= $(HOME)/source/claude-otel-stack/bin
WRAPPER_STAGE_DIR = .tmp-otel-stack-bin

stage-wrappers:  ## Copy claude/codex shims from OTEL_STACK_BIN into the build context
	@test -x $(OTEL_STACK_BIN)/claude && test -x $(OTEL_STACK_BIN)/codex || { \
	    echo "error: no executable claude and codex in $(OTEL_STACK_BIN) — set OTEL_STACK_BIN=<claude-otel-stack>/bin" >&2; \
	    exit 1; \
	}
	mkdir -p $(WRAPPER_STAGE_DIR)
	cp $(OTEL_STACK_BIN)/claude $(OTEL_STACK_BIN)/codex $(WRAPPER_STAGE_DIR)/

# The work image bakes this file in; see Containerfile.work. Refusing to build
# it when the source is absent is deliberate — a work image without the deny
# list looks normal and silently runs Anthropic models.
stage-managed-settings:  ## Copy the host's managed settings into the build context
	@test -f $(MANAGED_SETTINGS_SRC) || { \
	    echo "error: no managed settings at $(MANAGED_SETTINGS_SRC) — set MANAGED_SETTINGS_SRC=<path>" >&2; \
	    exit 1; \
	}
	cp $(MANAGED_SETTINGS_SRC) $(MANAGED_SETTINGS_STAGE)

clean:  ## Remove built images
	$(CONTAINER_TOOL) rmi $(IMAGE_REF) $(WORK_IMAGE_REF) 2>/dev/null || true

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
