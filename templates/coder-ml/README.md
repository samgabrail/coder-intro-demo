# Demo Overview

Prometheus metrics to check:

container_memory_usage_bytes{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}
container_cpu_usage_seconds_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}
container_cpu_cfs_periods_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}
max(rate(container_cpu_usage_seconds_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}[5m])) by (pod) * 100
max(rate(container_cpu_usage_seconds_total{namespace="coder", pod="coder-samgabrail-ml6-859d6bc44f-sp7l9"}[5m])) by (pod)