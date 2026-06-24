#!/usr/bin/env bash
# Port-forward all platform services to localhost (no cluster recreate required).
set -euo pipefail

NS="${K8S_NAMESPACE:-data-platform}"
PID_FILE="${K8S_DIR:-$(cd "$(dirname "$0")/.." && pwd)}/.port-forwards.pid"

stop_forwards() {
  if [[ -f "$PID_FILE" ]]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    echo "Stopped port-forwards."
  fi
}

if [[ "${1:-}" == "stop" ]]; then
  stop_forwards
  exit 0
fi

stop_forwards
: > "$PID_FILE"

forward() {
  local svc=$1 local_port=$2 remote_port=${3:-$2} ns="${4:-$NS}"
  kubectl -n "$ns" port-forward "svc/${svc}" "${local_port}:${remote_port}" \
    >/dev/null 2>&1 &
  echo $! >> "$PID_FILE"
  echo "  localhost:${local_port} -> ${ns}/${svc}:${remote_port}"
}

echo "Starting port-forwards (namespace: ${NS})..."
forward credit-api 8000 8000
forward mlflow 5000 5000
forward llm-api 8001 8000
forward llm-langgraph-api 8002 8000
forward trino 8086 8080
forward minio 9000 9000
forward minio 9001 9001
forward airflow-apiserver 8085 8080
forward spark-master 8083 8080
forward grafana 3000 3000 monitoring
forward prometheus 9090 9090 monitoring
forward alertmanager 9093 9093 monitoring

echo ""
echo "PIDs saved to ${PID_FILE}"
echo "Stop with: make port-forward-stop"
