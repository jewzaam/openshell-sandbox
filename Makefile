# openshell-sandbox

IMAGE_NAME ?= openshell-sandbox
IMAGE_TAG ?= latest
IMAGE_REF = $(IMAGE_NAME):$(IMAGE_TAG)
CONTAINER_TOOL ?= podman

.PHONY: build clean help

build:  ## Build the sandbox container image
	$(CONTAINER_TOOL) build -t $(IMAGE_REF) -f Containerfile .

clean:  ## Remove built image
	$(CONTAINER_TOOL) rmi $(IMAGE_REF) 2>/dev/null || true

help:  ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
