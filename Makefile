.PHONY: env cluster-up cluster-down build load-kind deploy up dry-run delete status restart

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

delete:
	kubectl kustomize --load-restrictor LoadRestrictionsNone platform/ | kubectl delete -f - --ignore-not-found

status:
	kubectl -n data-platform get pods,svc,pvc

restart:
	kubectl -n data-platform rollout restart deployment --all
