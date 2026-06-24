.PHONY: env cluster-up cluster-down build load-kind deploy up dry-run delete status restart port-forward port-forward-stop install-metrics-server hpa-status monitoring-status grafana

KIND_CLUSTER_NAME ?= data-platform
export KIND_CLUSTER_NAME

env:
	@test -f .env || cp .env.example .env
	@echo "Edit k8s/.env (HF_TOKEN, MLFLOW_MODEL_URI, etc.)"

# Create kind cluster + nginx ingress
cluster-up:
	bash scripts/create-kind-cluster.sh

cluster-down:
	bash scripts/delete-kind-cluster.sh

build:
	bash scripts/build-images.sh

load-kind:
	bash scripts/load-images-kind.sh

deploy: env
	cp .env base/secrets.env
	bash scripts/deploy.sh

# Full local workflow: cluster + build + load + deploy
up: env cluster-up build load-kind deploy

dry-run: env
	cp .env base/secrets.env
	kubectl kustomize --load-restrictor LoadRestrictionsNone platform/
	kubectl kustomize --load-restrictor LoadRestrictionsNone observability/

delete:
	kubectl kustomize --load-restrictor LoadRestrictionsNone observability/ | kubectl delete -f - --ignore-not-found
	kubectl kustomize --load-restrictor LoadRestrictionsNone platform/ | kubectl delete -f - --ignore-not-found

status:
	kubectl -n data-platform get pods,svc,pvc
	kubectl -n monitoring get pods,svc 2>/dev/null || true

restart:
	kubectl -n data-platform get deployments -o name | xargs -r -n 1 kubectl -n data-platform rollout restart

port-forward:
	bash scripts/port-forward-all.sh

port-forward-stop:
	bash scripts/port-forward-all.sh stop

install-metrics-server:
	bash scripts/install-metrics-server.sh

hpa-status:
	kubectl -n data-platform get hpa
	kubectl -n data-platform top pods 2>/dev/null || true

monitoring-status:
	kubectl -n monitoring get pods,svc
	@bash scripts/check-monitoring-access.sh

grafana:
	bash scripts/grafana-port-forward.sh
