#!/usr/bin/env bash
# Build local images and push to ECR (run after: terraform apply).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
TAG="${IMAGE_TAG:-latest}"

source "${K8S_DIR}/.env" 2>/dev/null || true

if [[ ! -d "${TF_DIR}/.terraform" ]] && [[ ! -f "${TF_DIR}/terraform.tfstate" ]]; then
  echo "Run 'terraform apply' in ${TF_DIR} first." >&2
  exit 1
fi

AWS_REGION="${AWS_REGION:-$(terraform -chdir="${TF_DIR}" output -raw aws_region)}"
ECR_REGISTRY="$(terraform -chdir="${TF_DIR}" output -raw ecr_registry)"
CLUSTER_NAME="$(terraform -chdir="${TF_DIR}" output -raw cluster_name)"

echo "==> ECR login (${ECR_REGISTRY})"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "==> Build images (same as make build)"
bash "${K8S_DIR}/scripts/build-images.sh"

declare -A IMAGE_MAP=(
  [mlflow]="local/mlflow:${TAG}"
  [credit-api]="local/credit-api:${TAG}"
  [hive-metastore]="local/hive-metastore:${TAG}"
  [spark-master]="local/spark-master:${TAG}"
  [spark-worker]="local/spark-worker:${TAG}"
  [llm-trino-mcp]="local/llm-trino-mcp:${TAG}"
  [llm-api]="local/llm-api:${TAG}"
  [llm-langgraph-api]="local/llm-langgraph-api:${TAG}"
)

for repo in "${!IMAGE_MAP[@]}"; do
  local_image="${IMAGE_MAP[$repo]}"
  remote="${ECR_REGISTRY}/${CLUSTER_NAME}/${repo}:${TAG}"
  echo "==> Push ${repo}"
  docker tag "${local_image}" "${remote}"
  docker push "${remote}"
done

# Airflow uses a fixed tag in manifests
AIRFLOW_TAG="3.1.0-libgomp"
remote_airflow="${ECR_REGISTRY}/${CLUSTER_NAME}/airflow:${AIRFLOW_TAG}"
docker tag "local/airflow:${AIRFLOW_TAG}" "${remote_airflow}"
docker push "${remote_airflow}"

echo ""
echo "Done. Images pushed to ${ECR_REGISTRY}/${CLUSTER_NAME}/"
