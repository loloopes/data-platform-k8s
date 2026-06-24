#!/usr/bin/env bash
# Create (or recreate) the kind cluster and install nginx ingress.
set -euo pipefail

K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER_NAME="${KIND_CLUSTER_NAME:-data-platform}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' already exists."
  echo "  kubectl cluster-info --context ${KIND_CONTEXT}"
  exit 0
fi

echo "Creating kind cluster '${CLUSTER_NAME}'..."
kind create cluster --name "${CLUSTER_NAME}" --config "${K8S_DIR}/kind-config.yaml"

echo ""
echo "Installing nginx ingress controller..."
kubectl --context "${KIND_CONTEXT}" apply -f \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo ""
echo "Waiting for ingress-nginx controller..."
for _ in $(seq 1 60); do
  if kubectl --context "${KIND_CONTEXT}" get deployment ingress-nginx-controller \
    -n ingress-nginx >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

kubectl --context "${KIND_CONTEXT}" rollout status deployment/ingress-nginx-controller \
  -n ingress-nginx --timeout=300s

echo ""
echo "Installing metrics-server (required for HPA autoscaling)..."
bash "${K8S_DIR}/scripts/install-metrics-server.sh"

echo ""
echo "Cluster ready. Context: ${KIND_CONTEXT}"
echo "Next: make build && make load-kind && make deploy"
