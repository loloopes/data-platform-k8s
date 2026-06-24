# Kubernetes — Data Platform (kind)

Deploys the full stack from this monorepo into a single namespace **`data-platform`** on a local **[kind](https://kind.sigs.k8s.io/)** cluster.

| Component | Source repo | K8s services |
|-----------|-------------|--------------|
| Credit / MLflow / Kafka | `credit_risk_forecast/` | `postgres`, `minio`, `mlflow`, `credit-api`, `kafka` |
| Trino lakehouse | `trino/` | `mysql`, `hive-metastore`, `trino`, `pgvector` |
| Spark | `spark-cluster/` | `spark-master`, `spark-worker` |
| LLM APIs | `llm/` | `llm-api`, `llm-langgraph-api` |
| Airflow | `credit_risk_forecast/` | `airflow-postgres`, `airflow-redis`, `airflow-apiserver`, scheduler, worker, … |
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
├── airflow/
├── ingress/
└── scripts/
    ├── create-kind-cluster.sh
    ├── load-images-kind.sh
    ├── delete-kind-cluster.sh
    ├── build-images.sh
    └── deploy.sh
```

## Localhost ports

Two ways to reach services from your machine:

### A) NodePort (persistent — requires cluster created with current `kind-config.yaml`)

| Service | localhost | Notes |
|---------|-----------|--------|
| Credit API | http://localhost:8000 | |
| MLflow | http://localhost:5000 | |
| LLM API | http://localhost:8001 | |
| LangGraph API | http://localhost:8002 | |
| **Trino** | **jdbc:trino://localhost:8086** | JDBC / SQL clients |
| MinIO S3 API | http://localhost:9000 | |
| MinIO console | http://localhost:9001 | |
| Airflow | http://localhost:8085 | user `airflow` / `airflow` |
| Spark UI | http://localhost:8083 | |

After `make deploy`, ports work immediately if the kind cluster was created with the port mappings above.  
**Existing cluster?** Recreate: `make cluster-down && make cluster-up && make deploy`

### B) Port-forward (works on any running cluster)

```bash
make port-forward        # start all forwards in background
make port-forward-stop   # stop them
```

### C) Ingress on port 80 (hostnames)

Add to `/etc/hosts`:

```
127.0.0.1 credit.local mlflow.local llm.local langgraph.local trino.local minio.local airflow.local
```

Then use e.g. http://trino.local (port 80, not 8086).

## Port-forward (manual)

| Service | Command | URL |
|---------|---------|-----|
| Credit API | `kubectl -n data-platform port-forward svc/credit-api 8000:8000` | http://localhost:8000 |
| MLflow | `kubectl -n data-platform port-forward svc/mlflow 5000:5000` | http://localhost:5000 |
| LLM API | `kubectl -n data-platform port-forward svc/llm-api 8001:8000` | http://localhost:8001/docs |
| LangGraph | `kubectl -n data-platform port-forward svc/llm-langgraph-api 8002:8000` | http://localhost:8002/docs |
| Trino | `kubectl -n data-platform port-forward svc/trino 8086:8080` | http://localhost:8086 |
| Airflow | `kubectl -n data-platform port-forward svc/airflow-apiserver 8085:8080` | http://localhost:8085 (airflow/airflow) |
| MinIO console | `kubectl -n data-platform port-forward svc/minio 9001:9001` | http://localhost:9001 |

## Ingress (optional)

`make cluster-up` installs nginx ingress and maps ports **80/443** on the host.

Add to `/etc/hosts` (WSL: `/etc/hosts`, Windows: `C:\Windows\System32\drivers\etc\hosts`):

```
127.0.0.1 credit.local mlflow.local llm.local langgraph.local trino.local minio.local airflow.local
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
| `local/airflow:3.1.0-libgomp` | `credit_risk_forecast/` (DAGs + config baked in) |
| `gruponddados/trino:469` | pulled by kind node |
| `pgvector/pgvector:pg16` | pulled by kind node |

## Airflow

CeleryExecutor stack matching `credit_risk_forecast/docker-compose.airflow.yml`:

- **airflow-postgres** / **airflow-redis** — metadata DB and Celery broker (separate from MLflow Postgres)
- **airflow-init** Job — DB migrate + admin user
- **airflow-apiserver** — UI and API (port 8080)
- **airflow-scheduler**, **airflow-dag-processor**, **airflow-worker**, **airflow-triggerer**

DAGs and `airflow.cfg` are baked into `local/airflow:3.1.0-libgomp` at build time. Rebuild after DAG changes:

```bash
make build && make load-kind
kubectl -n data-platform rollout restart deployment -l 'app in (airflow-apiserver,airflow-scheduler,airflow-dag-processor,airflow-worker,airflow-triggerer)'
```

**Note:** DockerOperator / NannyML docker-in-docker from compose is not mounted in k8s. Training and MLflow DAGs work against in-cluster MinIO/MLflow/credit-api.

## Trino catalogs

- `iceberg` — lakehouse tables (Hive Metastore + MinIO)
- `pgvector` — PostgreSQL with the `vector` extension (replaces ClickHouse)
- `tpch` / `tpcds` — benchmarks

Query pgvector from Trino: `SELECT * FROM pgvector.public.<table>` (after creating tables in Postgres).

## Not included (yet)

- Production HA, TLS, external S3/Postgres, GPU nodes for LLM
