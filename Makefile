# Multi-arch build support for Docker images
REGISTRY ?= ghcr.io
IMAGE_NAME ?= YOUR_USERNAME/opencode-analyzer
TAG ?= latest
FULL_IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(TAG)

# Platforms to build for
PLATFORMS = linux/amd64,linux/arm64

# Default target
.DEFAULT_GOAL := help

.PHONY: help build buildx push test local-build clean k8s-deploy k8s-delete

## Show this help message
help:
	@echo "OpenCode GitHub Analyzer - Build & Deploy"
	@echo ""
	@echo "Usage:"
	@echo "  make <target> [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@echo "  build          Build Docker image for local architecture"
	@echo "  buildx         Build multi-arch image using buildx (requires docker buildx)"
	@echo "  push           Build and push multi-arch image to registry"
	@echo "  test           Run tests (placeholder)"
	@echo "  local-build    Build and load image for local testing"
	@echo "  k8s-deploy     Deploy to Kubernetes (K3s)"
	@echo "  k8s-delete     Remove from Kubernetes"
	@echo "  clean          Clean up build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  REGISTRY       Container registry (default: ghcr.io)"
	@echo "  IMAGE_NAME     Image name (default: YOUR_USERNAME/opencode-analyzer)"
	@echo "  TAG            Image tag (default: latest)"
	@echo "  PLATFORMS      Target platforms (default: linux/amd64,linux/arm64)"
	@echo ""
	@echo "Examples:"
	@echo "  make build REGISTRY=myregistry.io IMAGE_NAME=myuser/opencode-analyzer"
	@echo "  make push TAG=v1.0.0"
	@echo "  make k8s-deploy"

## Build Docker image for local architecture only
build:
	@echo "Building Docker image for local architecture..."
	docker build -t $(FULL_IMAGE) .
	@echo "Built: $(FULL_IMAGE)"

## Build multi-arch image using docker buildx (does not push)
buildx:
	@echo "Building multi-arch image for platforms: $(PLATFORMS)"
	@echo "Note: This requires 'docker buildx create --use' first"
	docker buildx build \
		--platform $(PLATFORMS) \
		-t $(FULL_IMAGE) \
		.

## Build and push multi-arch image to registry
push:
	@echo "Building and pushing multi-arch image..."
	@echo "Target: $(FULL_IMAGE)"
	@echo "Platforms: $(PLATFORMS)"
	docker buildx build \
		--platform $(PLATFORMS) \
		-t $(FULL_IMAGE) \
		--push \
		.
	@echo "Pushed: $(FULL_IMAGE)"

## Build and load image for local testing (single arch only)
local-build:
	@echo "Building image for local testing..."
	docker buildx build \
		--load \
		-t $(FULL_IMAGE) \
		.
	@echo "Built and loaded: $(FULL_IMAGE)"

## Run tests (placeholder)
test:
	@echo "Running tests..."
	@echo "TODO: Add test suite"

## Setup docker buildx builder for multi-arch builds
setup-buildx:
	@echo "Setting up docker buildx..."
	@docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
	@docker buildx inspect --bootstrap
	@echo "Buildx builder ready"

## Clean up Docker images and build cache
clean:
	@echo "Cleaning up..."
	-docker rmi $(FULL_IMAGE) 2>/dev/null || true
	-docker buildx prune -f 2>/dev/null || true
	@echo "Cleanup complete"

## Deploy to Kubernetes (K3s)
k8s-deploy:
	@echo "Deploying to Kubernetes..."
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/configmap-repos.yaml
	kubectl apply -f k8s/secret-github-token.yaml
	kubectl apply -f k8s/pvc-output.yaml
	kubectl apply -f k8s/cronjob.yaml
	@echo ""
	@echo "Deployment complete! Check status with:"
	@echo "  kubectl get all -n opencode-analyzer"
	@echo ""
	@echo "IMPORTANT: Update k8s/secret-github-token.yaml with your GitHub token!"
	@echo "IMPORTANT: Update k8s/configmap-repos.yaml with your repositories!"

## Remove from Kubernetes
k8s-delete:
	@echo "Removing from Kubernetes..."
	kubectl delete -f k8s/ --ignore-not-found=true
	@echo "Removal complete"

## Trigger a manual job run now
k8s-run-now:
	@echo "Triggering manual job run..."
	kubectl create job --from=cronjob/opencode-analyzer manual-run-$(shell date +%s) -n opencode-analyzer
	@echo "Job triggered. Check logs with:"
	@echo "  kubectl logs -n opencode-analyzer -l job-name=manual-run-*"

## View CronJob logs
k8s-logs:
	@echo "Viewing logs..."
	kubectl logs -n opencode-analyzer -l app=opencode-analyzer --tail=100 -f

## Check deployment status
k8s-status:
	@echo "Checking deployment status..."
	kubectl get all -n opencode-analyzer
	@echo ""
	kubectl get pvc -n opencode-analyzer
	@echo ""
	kubectl get configmap -n opencode-analyzer
