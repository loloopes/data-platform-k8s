#!/usr/bin/env bash
# Build local images referenced by k8s manifests (kind/minikube/docker-desktop).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${IMAGE_TAG:-latest}"

source "${K8S_DIR}/.env" 2>/dev/null || true
HF_TOKEN="${HF_TOKEN:-}"
SKIP_PREFETCH="${SKIP_PREFETCH:-true}"
BASE_MODEL="${BASE_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
ADAPTER_REPO="${ADAPTER_REPO:-Glccampos/llm_qween}"

echo "==> MLflow"
docker build -t "local/mlflow:${TAG}" "${ROOT}/credit_risk_forecast/docker/mlflow"

echo "==> credit-api"
docker build -t "local/credit-api:${TAG}" -f "${ROOT}/credit_risk_forecast/prod/dockerfile" "${ROOT}/credit_risk_forecast/prod"

echo "==> hive-metastore"
docker build -t "local/hive-metastore:${TAG}" "${ROOT}/trino/hive-metastore"

echo "==> spark-master"
docker build -t "local/spark-master:${TAG}" "${ROOT}/spark-cluster/spark-master"

echo "==> spark-worker"
docker build -t "local/spark-worker:${TAG}" "${ROOT}/spark-cluster/spark-worker"

echo "==> llm-trino-mcp"
docker build -t "local/llm-trino-mcp:${TAG}" "${ROOT}/mcp"

echo "==> llm-api"
docker build -t "local/llm-api:${TAG}" \
  --build-arg HF_TOKEN="${HF_TOKEN}" \
  --build-arg SKIP_PREFETCH="${SKIP_PREFETCH}" \
  --build-arg BASE_MODEL="${BASE_MODEL}" \
  --build-arg ADAPTER_REPO="${ADAPTER_REPO}" \
  -f "${ROOT}/llm/api/Dockerfile" "${ROOT}/llm/api"

echo "==> llm-langgraph-api"
docker tag "local/llm-api:${TAG}" "local/llm-langgraph-api:${TAG}"

echo "==> airflow"
docker build -t "local/airflow:3.1.0-libgomp" -f "${K8S_DIR}/airflow/Dockerfile" "${ROOT}/credit_risk_forecast"

echo "Done. Images tagged with :${TAG}"
