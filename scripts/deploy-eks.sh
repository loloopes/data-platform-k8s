#!/usr/bin/env bash
# Deploy platform manifests to EKS (ECR images + kustomize overlay).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
AIRFLOW_TAG="3.1.0-libgomp"

AWS_REGION="${AWS_REGION:-$(terraform -chdir="${TF_DIR}" output -raw aws_region)}"
ECR_REGISTRY="$(terraform -chdir="${TF_DIR}" output -raw ecr_registry)"
CLUSTER_NAME="$(terraform -chdir="${TF_DIR}" output -raw cluster_name)"
INGRESS_TYPE="$(terraform -chdir="${TF_DIR}" output -raw ingress_type)"

ecr_image() {
  echo "${ECR_REGISTRY}/${CLUSTER_NAME}/$1:$2"
}

render_alb_ingress() {
  local base_domain cert_arn
  base_domain="$(terraform -chdir="${TF_DIR}" output -raw base_domain)"
  cert_arn="$(terraform -chdir="${TF_DIR}" output -raw acm_certificate_arn)"

  if [[ -z "${base_domain}" || -z "${cert_arn}" ]]; then
    echo "ERROR: ALB ingress requires base_domain and acm_certificate_arn in terraform outputs." >&2
    echo "  Set base_domain + route53_zone_id in terraform.tfvars, or pass acm_certificate_arn." >&2
    exit 1
  fi

  sed \
    -e "s|__BASE_DOMAIN__|${base_domain}|g" \
    -e "s|__ACM_CERTIFICATE_ARN__|${cert_arn}|g" \
    "${K8S_DIR}/ingress-eks/ingress-alb.yaml"
}

llm_use_gpu() {
  local raw="${LLM_USE_GPU:-}"
  if [[ -z "${raw}" && -f "${K8S_DIR}/.env" ]]; then
    raw="$(grep -E '^LLM_USE_GPU=' "${K8S_DIR}/.env" | tail -1 | cut -d= -f2- | tr -d " '\"" || true)"
  fi
  case "${raw,,}" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

echo "==> Configure kubectl for ${CLUSTER_NAME}"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

echo "==> Prepare secrets from k8s/.env"
if [[ ! -f "${K8S_DIR}/.env" ]]; then
  cp "${K8S_DIR}/.env.example" "${K8S_DIR}/.env"
  echo "Created k8s/.env from example — edit secrets before production use."
fi
cp "${K8S_DIR}/.env" "${K8S_DIR}/base/secrets.env"

# Use IMAGE_TAG from k8s/.env unless explicitly overridden in the shell.
if [[ -z "${IMAGE_TAG:-}" ]]; then
  IMAGE_TAG="$(grep -E '^IMAGE_TAG=' "${K8S_DIR}/.env" | tail -1 | cut -d= -f2- | tr -d " '\"" || true)"
fi
TAG="${IMAGE_TAG:-latest}"
echo "==> Image tag: ${TAG}"

cd "${K8S_DIR}"

OVERLAY="platform-eks"
if [[ "${INGRESS_TYPE}" == "alb" ]]; then
  OVERLAY="platform-eks-alb"
fi
if llm_use_gpu; then
  OVERLAY="${OVERLAY}-gpu"
  echo "==> LLM GPU mode enabled (LLM_USE_GPU=true → overlay ${OVERLAY})"
else
  echo "==> LLM CPU mode (set LLM_USE_GPU=true in k8s/.env for GPU nodes)"
fi

echo "==> Render manifests (${OVERLAY} overlay + ECR images)"
MANIFEST="$(kubectl kustomize --load-restrictor LoadRestrictionsNone "${OVERLAY}")"
MANIFEST="${MANIFEST//local\/mlflow:latest/$(ecr_image mlflow "${TAG}")}"
MANIFEST="${MANIFEST//local\/credit-api:latest/$(ecr_image credit-api "${TAG}")}"
MANIFEST="${MANIFEST//local\/hive-metastore:latest/$(ecr_image hive-metastore "${TAG}")}"
MANIFEST="${MANIFEST//local\/spark-master:latest/$(ecr_image spark-master "${TAG}")}"
MANIFEST="${MANIFEST//local\/spark-worker:latest/$(ecr_image spark-worker "${TAG}")}"
MANIFEST="${MANIFEST//local\/llm-trino-mcp:latest/$(ecr_image llm-trino-mcp "${TAG}")}"
MANIFEST="${MANIFEST//local\/llm-api:latest/$(ecr_image llm-api "${TAG}")}"
MANIFEST="${MANIFEST//local\/llm-langgraph-api:latest/$(ecr_image llm-langgraph-api "${TAG}")}"
MANIFEST="${MANIFEST//local\/airflow:3.1.0-libgomp/$(ecr_image airflow "${AIRFLOW_TAG}")}"

if [[ "${INGRESS_TYPE}" == "alb" ]]; then
  MANIFEST="${MANIFEST}"$'\n'"$(render_alb_ingress)"
fi

echo "==> Delete init jobs (immutable) then apply"
kubectl -n data-platform delete job airflow-init minio-init kafka-init --ignore-not-found 2>/dev/null || true
echo "${MANIFEST}" | kubectl apply -f -
kubectl kustomize --load-restrictor LoadRestrictionsNone observability | kubectl apply -f -

echo ""
if [[ "${INGRESS_TYPE}" == "alb" ]]; then
  echo "==> ALB ingress (may take 2–3 min for AWS to provision)"
  echo "  kubectl -n data-platform get ingress platform-ingress"
  echo ""
  terraform -chdir="${TF_DIR}" output -json platform_urls 2>/dev/null || true
  echo ""
  echo "Point DNS at the ALB hostname (wildcard recommended):"
  BASE_DOMAIN="$(terraform -chdir="${TF_DIR}" output -raw base_domain)"
  echo "  *.${BASE_DOMAIN} → \$(kubectl -n data-platform get ingress platform-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
else
  echo "==> Ingress LoadBalancer (may take 2–3 min)"
  echo "  kubectl -n ingress-nginx get svc ingress-nginx-controller"
  echo ""
  echo "Point DNS (or /etc/hosts) at the LB hostname for: credit.local, mlflow.local, airflow.local, …"
fi
echo ""
echo "Watch rollout: kubectl -n data-platform get pods -w"
