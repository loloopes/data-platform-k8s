#!/usr/bin/env bash
# Delete the kind cluster (does not remove host Docker images).
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-data-platform}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "Deleted kind cluster '${CLUSTER_NAME}'"
else
  echo "No kind cluster named '${CLUSTER_NAME}'"
fi
