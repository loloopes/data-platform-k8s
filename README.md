# Kubernetes — Data Platform (kind)

Deploys the full stack from this monorepo into a single namespace **`data-platform`** on a local **[kind](https://kind.sigs.k8s.io/)** cluster.

| Component | Source repo | K8s services |
|-----------|-------------|--------------|
| Credit / MLflow / Kafka | `credit_risk_forecast/` | `postgres`, `minio`, `mlflow`, `credit-api`, `kafka` |
| Trino lakehouse | `trino/` | `mysql`, `hive-metastore`, `trino`, `pgvector` |
| Spark | `spark-cluster/` | `spark-master`, `spark-worker` |
| LLM APIs | `llm/` | `llm-api`, `llm-langgraph-api` |
| Trino MCP | `mcp/` | `llm-trino-mcp` |

Service DNS names match Docker Compose (`minio`, `trino`, `kafka`, …) so existing app config works unchanged.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- `kubectl`

**Resource hint:** LLM pods need ~4–8 GB RAM on first start (model download). The full stack is dev-oriented.

## Quick start (kind)

```bash
cd k8s

# 1. Configure secrets
cp .env.example .env
# edit .env — HF_TOKEN, MLFLOW_MODEL_URI, etc.

# 2. One-shot: create cluster, build images, load into kind, deploy
make up

# 3. Watch pods
make status
# or: kubectl -n data-platform get pods -w
```

### Step by step

```bash
make cluster-up    # kind cluster "data-platform" + nginx ingress
make build         # build local/* images on host Docker
make load-kind     # kind load docker-image … (required after every rebuild)
make deploy
```

After changing images:

```bash
make build && make load-kind && make restart
```

## Why `load-kind`?

kind nodes run in Docker but **do not see host images automatically**. `make build` tags images on your machine; `make load-kind` copies them into the kind node. Without this step you get `ErrImagePull` on `local/*` images.

## Teardown

```bash
make delete        # remove k8s resources (keeps PVCs)
make cluster-down  # delete the kind cluster
```

## Layout

```
k8s/
├── kind-config.yaml              # kind cluster definition
├── platform/kustomization.yaml   # root overlay (apply this)
├── base/                         # namespace, secrets, shared config
├── credit-risk/
├── trino/
├── spark/
├── mcp/
├── llm/
├── ingress/
└── scripts/
    ├── create-kind-cluster.sh
    ├── load-images-kind.sh
    ├── delete-kind-cluster.sh
    ├── build-images.sh
    └── deploy.sh
```

## Port-forward (local access)

| Service | Command | URL |
|---------|---------|-----|
| Credit API | `kubectl -n data-platform port-forward svc/credit-api 8000:8000` | http://localhost:8000 |
| MLflow | `kubectl -n data-platform port-forward svc/mlflow 5000:5000` | http://localhost:5000 |
| LLM API | `kubectl -n data-platform port-forward svc/llm-api 8001:8000` | http://localhost:8001/docs |
| LangGraph | `kubectl -n data-platform port-forward svc/llm-langgraph-api 8002:8000` | http://localhost:8002/docs |
| Trino | `kubectl -n data-platform port-forward svc/trino 8086:8080` | http://localhost:8086 |
| MinIO console | `kubectl -n data-platform port-forward svc/minio 9001:9001` | http://localhost:9001 |

## Ingress (optional)

`make cluster-up` installs nginx ingress and maps ports **80/443** on the host.

Add to `/etc/hosts` (WSL: `/etc/hosts`, Windows: `C:\Windows\System32\drivers\etc\hosts`):

```
127.0.0.1 credit.local mlflow.local llm.local langgraph.local trino.local minio.local
```

## Makefile targets

| Target | Description |
|--------|-------------|
| `make up` | cluster-up + build + load-kind + deploy |
| `make cluster-up` | Create kind cluster + ingress |
| `make cluster-down` | Delete kind cluster |
| `make build` | Build all `local/*` images |
| `make load-kind` | Load images into kind |
| `make deploy` | Apply manifests |
| `make restart` | Rollout restart all deployments |
| `make status` | Pod/service status |
| `make delete` | Remove workloads from cluster |

## Images

| Image | Build context |
|-------|---------------|
| `local/mlflow:latest` | `credit_risk_forecast/docker/mlflow` |
| `local/credit-api:latest` | `credit_risk_forecast/prod` |
| `local/hive-metastore:latest` | `trino/hive-metastore` |
| `local/spark-master:latest` | `spark-cluster/spark-master` |
| `local/spark-worker:latest` | `spark-cluster/spark-worker` |
| `local/llm-api:latest` | `llm/api` |
| `local/llm-langgraph-api:latest` | same as llm-api |
| `local/llm-trino-mcp:latest` | `mcp` |
| `gruponddados/trino:469` | pulled by kind node |
| `pgvector/pgvector:pg16` | pulled by kind node |

## Trino catalogs

- `iceberg` — lakehouse tables (Hive Metastore + MinIO)
- `pgvector` — PostgreSQL with the `vector` extension (replaces ClickHouse)
- `tpch` / `tpcds` — benchmarks

Query pgvector from Trino: `SELECT * FROM pgvector.public.<table>` (after creating tables in Postgres).

## Not included (yet)

- **Airflow** — separate overlay
- Production HA, TLS, external S3/Postgres, GPU nodes for LLM
