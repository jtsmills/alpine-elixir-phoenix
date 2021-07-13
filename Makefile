.PHONY: help

ALPINE_VERSION ?= `cat VERSION | grep alpine | cut -d' ' -f2`
ALPINE_MIN_VERSION := $(shell echo $(ALPINE_VERSION) | sed 's/\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(\.[0-9][0-9]*\)*/\1.\2/')
ERLANG_VERSION ?= `cat VERSION | grep erlang | cut -d' ' -f2`
ELIXIR_VERSION ?= `cat VERSION | grep elixir | cut -d' ' -f2`
VERSION := $(ERLANG_VERSION)-$(ELIXIR_VERSION)
IMAGE_NAME ?= eglimi/alpine-elixir-phoenix
XDG_CACHE_HOME ?= /tmp
BUILDX_CACHE_DIR ?= $(XDG_CACHE_HOME)/buildx

help:
	@echo "$(IMAGE_NAME):$(VERSION) (alpine $(ALPINE_VERSION))"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

test: ## Test the Docker image
	docker run --rm -it $(IMAGE_NAME):$(VERSION) elixir --version

shell: ## Run an Elixir shell in the image
	docker run --rm -it $(IMAGE_NAME):$(VERSION) iex

sh: ## Boot to a shell prompt
	docker run --rm -it $(IMAGE_NAME):$(VERSION) /bin/bash

setup-buildx: ## Setup a Buildx builder
	@mkdir -p "$(BUILDX_CACHE_DIR)"
	@if ! docker buildx ls | grep buildx-builder >/dev/null; then \
		docker buildx create --append --name buildx-builder --driver docker-container --use && \
		docker buildx inspect --bootstrap --builder buildx-builder; \
	fi

build: setup-buildx ## Build the Docker image
	docker buildx build --output "type=image,push=false" \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--build-arg ERLANG_VERSION=$(ERLANG_VERSION) \
		--build-arg ELIXIR_VERSION=$(ELIXIR_VERSION) \
		--platform linux/amd64,linux/arm/v7 \
		--cache-from "type=local,src=$(BUILDX_CACHE_DIR)" \
		--cache-to "type=local,dest=$(BUILDX_CACHE_DIR)" \
		-t $(IMAGE_NAME):$(VERSION) .

.PHONY: build-local
build-local: setup-buildx
	docker buildx build --load \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--build-arg ERLANG_VERSION=$(ERLANG_VERSION) \
		--build-arg ELIXIR_VERSION=$(ELIXIR_VERSION) \
		--cache-from "type=local,src=$(BUILDX_CACHE_DIR)" \
		--cache-to "type=local,dest=$(BUILDX_CACHE_DIR)" \
		--platform linux/amd64 \
		-t $(IMAGE_NAME):$(VERSION) .

clean: ## Clean up generated images
	@docker rmi --force $(IMAGE_NAME):$(VERSION)

rebuild: clean build ## Rebuild the Docker image

release: setup-buildx ## Build and release the Docker image to Docker Hub
	docker buildx build --push \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--build-arg ERLANG_VERSION=$(ERLANG_VERSION) \
		--build-arg ELIXIR_VERSION=$(ELIXIR_VERSION) \
		--platform linux/amd64,linux/arm/v7 \
		--cache-from "type=local,src=$(BUILDX_CACHE_DIR)" \
		--cache-to "type=local,dest=$(BUILDX_CACHE_DIR)" \
		-t $(IMAGE_NAME):$(VERSION) .
