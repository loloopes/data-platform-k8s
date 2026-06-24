# Build context: credit_risk_forecast/
FROM apache/airflow:3.1.0

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/airflow/requirements-af.txt /opt/airflow/requirements-af.txt

USER airflow
RUN pip install --no-cache-dir -r /opt/airflow/requirements-af.txt

COPY --chown=airflow:root dags /opt/airflow/dags
COPY --chown=airflow:root config/airflow.cfg /opt/airflow/config/airflow.cfg
RUN mkdir -p /opt/airflow/logs /opt/airflow/plugins
