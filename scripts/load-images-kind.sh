#!/usr/bin/env bash
# Load locally built images into the kind cluster (fixes ErrImagePull on local/* images).
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-data-platform}"
TAG="${IMAGE_TAG:-latest}"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind not found — install: https://kind.sigs.k8s.io/docs/user/quick-start/" >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' not found. Run: make cluster-up" >&2
  exit 1
fi

IMAGES=(
  "local/mlflow:${TAG}"
  "local/credit-api:${TAG}"
  "local/hive-metastore:${TAG}"
  "local/spark-master:${TAG}"
  "local/spark-worker:${TAG}"
  "local/llm-trino-mcp:${TAG}"
  "local/llm-api:${TAG}"
  "local/llm-langgraph-api:${TAG}"
  "local/airflow:3.1.0-libgomp"
)

echo "Loading images into kind cluster '${CLUSTER_NAME}'..."
for img in "${IMAGES[@]}"; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "  -> $img"
    kind load docker-image "$img" --name "${CLUSTER_NAME}"
  else
    echo "  !! skip (not built): $img — run: make build" >&2
  fi
done

echo "Done."
