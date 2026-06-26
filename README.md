# Kubernetes — Data Platform (kind)

Deploys the full stack from this monorepo into a single namespace **`data-platform`**.

- **Local (kind):** see Quick start below.
- **AWS EKS:** see [`../terraform/README.md`](../terraform/README.md) — VPC, EKS, ECR, ALB + ACM, remote state, and deploy scripts.

| Component | Source repo | K8s services |
|-----------|-------------|--------------|
| Credit / MLflow / Kafka | `credit_risk_forecast/` | `mlflow-postgres`, `minio`, `mlflow`, `credit-api`, `kafka` |
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
├── autoscaling/                  # HPAs + CPU/memory requests for stateless workloads
├── observability/                # Prometheus, Grafana, Alertmanager, kube-state-metrics
├── ingress/
└── scripts/
    ├── create-kind-cluster.sh
    ├── install-metrics-server.sh
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
| **Grafana** | **http://localhost:3000** | user `admin` / `admin` |
| Prometheus | http://localhost:9090 | metrics + alert rules |
| Alertmanager | http://localhost:9093 | firing alerts |

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
| Grafana | `kubectl -n monitoring port-forward svc/grafana 3000:3000` | http://localhost:3000 (admin/admin) |
| Prometheus | `kubectl -n monitoring port-forward svc/prometheus 9090:9090` | http://localhost:9090 |
| Alertmanager | `kubectl -n monitoring port-forward svc/alertmanager 9093:9093` | http://localhost:9093 |

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
| `make hpa-status` | Show HPAs and pod CPU/memory usage |
| `make monitoring-status` | Observability pods + UI URLs |
| `make install-metrics-server` | Install metrics-server (also runs on `cluster-up`) |
| `make delete` | Remove workloads from cluster |

## Horizontal autoscaling

`make cluster-up` installs **metrics-server** (required for CPU-based HPA). Stateless workloads scale automatically via `HorizontalPodAutoscaler` in `autoscaling/`:

| Deployment | Min | Max | Trigger |
|------------|-----|-----|---------|
| `credit-api` | 1 | 5 | CPU 70% (idle stays at 1) |
| `llm-api` | 1 | 3 | CPU 75% |
| `llm-langgraph-api` | 1 | 3 | CPU 75% |
| `llm-trino-mcp` | 1 | 3 | CPU 70% |
| `spark-worker` | 1 | 4 | CPU 70% |
| `airflow-worker` | 1 | 5 | CPU 70% |

Check scaling status:

```bash
make hpa-status
# or: kubectl -n data-platform get hpa
```

**Does not scale horizontally** (single-replica by design on kind):

- Databases and brokers: `mlflow-postgres`, `mysql`, `minio`, `kafka`, `pgvector`, `airflow-postgres`, `airflow-redis`
- Coordinators / singletons: `mlflow`, `airflow-apiserver`, `trino`, `hive-metastore`, `spark-master`, `airflow-scheduler`, `airflow-dag-processor`, `airflow-triggerer`

**Multi-replica notes:**

- LLM pods use per-pod `emptyDir` for the Hugging Face cache (no shared PVC), so extra replicas can schedule on different nodes; each pod may download the model on first start.
- `credit-api` no longer sets a fixed pod `hostname`, so Spark driver callbacks work with multiple replicas via the `credit-api` Service.

For production HA of stateful services, use managed databases, object storage, and a Trino cluster with separate coordinator/workers.

## Observability (Prometheus + Grafana)

Deployed into namespace **`monitoring`** on every `make deploy`:

| Component | Role |
|-----------|------|
| **Prometheus** | Scrapes kube-state-metrics, cAdvisor (pod CPU/memory), and pods with `prometheus.io/scrape: "true"` |
| **kube-state-metrics** | HPA, deployment, and pod state metrics |
| **Grafana** | Pre-provisioned dashboards for HPA, workloads, and alerts |
| **Alertmanager** | Routes Prometheus alert rules (HPA at max, crash loops, high CPU/memory) |

Open Grafana: **http://localhost:3000** (`admin` / `admin`)

Pre-built dashboards (folder **Data Platform**):

- **HPA Overview** — current/desired/max replicas, scaling lag
- **Workload Resources** — CPU & memory vs limits, deployment replicas, restarts
- **Alerts Overview** — firing alerts and scrape health

```bash
make monitoring-status
```

**App-level `/metrics`:** Pods in `data-platform` are auto-scraped when annotated:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8000"
    prometheus.io/path: "/metrics"
```

Most services do not expose Prometheus metrics yet; workload dashboards use cAdvisor + kube-state-metrics.

**Alert routing:** Alertmanager uses in-cluster receivers (no Slack/email) for local dev. Edit `observability/alertmanager.yaml` to add webhooks.

**Existing kind cluster?** Recreate to pick up NodePort mappings for Grafana/Prometheus: `make cluster-down && make cluster-up && make deploy`

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

- **mlflow-postgres** — dedicated Postgres for MLflow tracking (`mlflow` DB) and auth (`mlflow_auth` DB). Databases are created once on first PVC init (`docker-entrypoint-initdb.d`); data persists across MLflow pod restarts.
- **airflow-postgres** / **airflow-redis** — metadata DB and Celery broker (separate from MLflow)
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

- Production HA for stateful services (Postgres, MinIO, Kafka, Trino coordinator), TLS, external S3/Postgres, GPU nodes for LLM
- Queue-based autoscaling for Airflow workers (e.g. KEDA on Redis queue depth)
