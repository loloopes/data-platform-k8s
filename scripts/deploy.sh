#!/usr/bin/env bash
set -euo pipefail

K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${K8S_DIR}"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-data-platform}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

if [[ -f .env ]]; then
  :
else
  echo "Creating k8s/.env from .env.example — edit HF_TOKEN and MLflow model URIs before production use."
  cp .env.example .env
fi

cp .env base/secrets.env

if command -v kubectl >/dev/null 2>&1; then
  if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KIND_CONTEXT}"; then
    kubectl config use-context "${KIND_CONTEXT}"
  fi
fi

echo "==> kubectl apply (context: $(kubectl config current-context 2>/dev/null || echo unknown))"
kubectl kustomize --load-restrictor LoadRestrictionsNone platform/ | kubectl apply -f -

if command -v kind >/dev/null 2>&1; then
  echo ""
  echo "kind: load local images after every rebuild:"
  echo "  make load-kind && make restart"
fi

echo ""
echo "Watch rollout:"
echo "  kubectl -n data-platform get pods -w"
echo ""
echo "Port-forward examples:"
echo "  kubectl -n data-platform port-forward svc/credit-api 8000:8000"
echo "  kubectl -n data-platform port-forward svc/llm-api 8001:8000"
echo "  kubectl -n data-platform port-forward svc/llm-langgraph-api 8002:8000"
echo "  kubectl -n data-platform port-forward svc/trino 8086:8080"
echo "  kubectl -n data-platform port-forward svc/mlflow 5000:5000"
