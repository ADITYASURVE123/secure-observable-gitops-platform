SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# ---- Pinned tool versions (bump deliberately) -------------------------------------------
CLUSTER        ?= gitops-platform
TRAEFIK_CHART  ?= 39.0.9
OVERLAY        ?= dev
NAMESPACE      ?= orders
API_IMAGE      ?= orders-api:dev
FRONTEND_IMAGE ?= orders-frontend:dev
VERSION        ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

.PHONY: help cluster-up build load secrets deploy test smoke status teardown jenkins-up jenkins-down jenkins-logs jenkins-lock

help: ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

cluster-up: ## Create the Kind cluster and install the Traefik ingress controller
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind/kind-config.yaml
	helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
	helm repo update traefik >/dev/null
	helm upgrade --install traefik traefik/traefik --version $(TRAEFIK_CHART) \
	  --namespace traefik --create-namespace -f kind/traefik-values.yaml --wait --timeout 3m

build: ## Build both images locally
	docker build --target runtime --build-arg APP_VERSION=$(VERSION) -t $(API_IMAGE) app/api
	docker build --build-arg BUILD_VERSION=$(VERSION) -t $(FRONTEND_IMAGE) app/frontend

load: build ## Side-load the images into Kind (no registry needed locally)
	kind load docker-image $(API_IMAGE) $(FRONTEND_IMAGE) --name $(CLUSTER)

secrets: ## Create the DB Secret (random password, never written to disk or Git)
	./scripts/create-secrets.sh

deploy: load secrets ## Build, load and deploy the dev overlay; wait for rollout
	kubectl apply -k k8s/overlays/$(OVERLAY)
	kubectl -n $(NAMESPACE) rollout status statefulset/postgres --timeout=180s
	kubectl -n $(NAMESPACE) rollout status deployment/api --timeout=180s
	kubectl -n $(NAMESPACE) rollout status deployment/frontend --timeout=120s
	@echo "App is up: http://localhost:8080"

test: ## Unit tests (in Docker), manifest rendering, then smoke test if the cluster is up
	docker build --target test app/api
	kubectl kustomize k8s/overlays/dev >/dev/null && echo "dev overlay renders"
	kubectl kustomize k8s/overlays/staging >/dev/null && echo "staging overlay renders"
	@if kubectl -n $(NAMESPACE) get deploy api >/dev/null 2>&1; then ./scripts/smoke-test.sh; \
	else echo "cluster app not deployed - skipping smoke test (run 'make deploy')"; fi

smoke: ## Smoke test against http://localhost:8080
	./scripts/smoke-test.sh

status: ## Show pods and ingress
	kubectl -n $(NAMESPACE) get pods,svc,ingress -o wide

jenkins-up: ## Start Jenkins (JCasC) + docker-in-docker; creates ci/.env on first run
	./ci/scripts/init-env.sh
	docker compose -f ci/docker-compose.yml up -d --build
	@echo "Jenkins: http://localhost:8081  (user: admin, password: JENKINS_ADMIN_PASSWORD in ci/.env)"

jenkins-down: ## Stop Jenkins (keeps volumes; add -v manually to wipe state)
	docker compose -f ci/docker-compose.yml down

jenkins-logs: ## Follow Jenkins logs
	docker compose -f ci/docker-compose.yml logs -f jenkins

jenkins-lock: ## Resolve Jenkins plugins to exact versions -> ci/plugins.lock.txt (commit it)
	./ci/scripts/lock-plugins.sh

teardown: ## Delete the Kind cluster
	kind delete cluster --name $(CLUSTER)
