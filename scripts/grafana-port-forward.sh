#!/usr/bin/env bash
# Open Grafana via port-forward when kind NodePort mappings are missing.
set -euo pipefail

NS="${K8S_NAMESPACE:-monitoring}"
LOCAL_PORT="${GRAFANA_LOCAL_PORT:-3000}"

if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "Namespace ${NS} not found. Run: make deploy"
  exit 1
fi

if ! kubectl -n "$NS" get svc grafana >/dev/null 2>&1; then
  echo "Grafana service not found. Run: make deploy"
  exit 1
fi

if curl -sf --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/api/health" >/dev/null 2>&1; then
  echo "Grafana already reachable at http://localhost:${LOCAL_PORT}"
  echo "Login: admin / admin"
  exit 0
fi

echo "Grafana is not reachable on localhost:${LOCAL_PORT}."
echo "Your kind cluster likely predates observability port mappings in kind-config.yaml."
echo ""
echo "Quick fix (this terminal — keep it open):"
echo "  kubectl -n ${NS} port-forward svc/grafana ${LOCAL_PORT}:3000"
echo ""
echo "Permanent fix (recreate cluster with current kind-config.yaml):"
echo "  make cluster-down && make cluster-up && make deploy"
echo ""
echo "Starting port-forward now..."
exec kubectl -n "$NS" port-forward "svc/grafana" "${LOCAL_PORT}:3000"
