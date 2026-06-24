#!/usr/bin/env bash
set -euo pipefail

check() {
  local name=$1 port=$2
  if curl -sf --max-time 2 "http://127.0.0.1:${port}/api/health" >/dev/null 2>&1; then
    echo "  ${name}: http://localhost:${port}  OK"
    return 0
  fi
  if curl -sf --max-time 2 "http://127.0.0.1:${port}/-/ready" >/dev/null 2>&1; then
    echo "  ${name}: http://localhost:${port}  OK"
    return 0
  fi
  if curl -sf --max-time 2 "http://127.0.0.1:${port}/-/healthy" >/dev/null 2>&1; then
    echo "  ${name}: http://localhost:${port}  OK"
    return 0
  fi
  echo "  ${name}: http://localhost:${port}  NOT REACHABLE"
  return 1
}

echo ""
echo "Monitoring UIs (login Grafana: admin / admin):"
grafana_ok=0
prom_ok=0
am_ok=0
check Grafana 3000 && grafana_ok=1 || true
check Prometheus 9090 && prom_ok=1 || true
check Alertmanager 9093 && am_ok=1 || true

if [[ "$grafana_ok" -eq 0 || "$prom_ok" -eq 0 || "$am_ok" -eq 0 ]]; then
  echo ""
  echo "Port not open? Either:"
  echo "  make port-forward          # background forwards for all services"
  echo "  make grafana               # foreground Grafana only"
  echo "  make cluster-down && make cluster-up && make deploy   # kind NodePort mappings"
fi
