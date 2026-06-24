#!/usr/bin/env bash
# metrics-server is required for HorizontalPodAutoscaler CPU/memory metrics.
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-data-platform}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

kubectl --context "${KIND_CONTEXT}" apply -f \
  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl --context "${KIND_CONTEXT}" patch deployment metrics-server -n kube-system --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'

kubectl --context "${KIND_CONTEXT}" rollout status deployment/metrics-server -n kube-system --timeout=120s
echo "metrics-server ready."
