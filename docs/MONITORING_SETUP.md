# Monitoring Setup - Todo App on CNAP Cluster

This document details the monitoring configuration added after the initial deployment fixes.

---

## Overview

Added Prometheus metrics scraping and Grafana dashboard for the Todo application stack.

**Components Monitored:**
- Todo API (Spring Boot backend)
- MySQL Database
- JVM Metrics
- HikariCP Connection Pool

---

## Changes Made

### 1. Backend Metrics Endpoint

Added Spring Boot Actuator with Prometheus metrics exporter.

**File:** `todo/Backend/pom.xml`

```xml
<!-- Added dependencies -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

**File:** `todo/Backend/src/main/resources/application.properties`

```properties
# Added Actuator configuration
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.prometheus.enabled=true
management.metrics.export.prometheus.enabled=true
```

**Result:** Metrics available at `/actuator/prometheus`

---

### 2. ServiceMonitor for Todo API

Created Prometheus ServiceMonitor to scrape the backend.

**File:** `todo/k8s/servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: todo-api
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: todo-api
  namespaceSelector:
    matchNames:
      - testswilts
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
```

**Why `release: kube-prometheus-stack` label?**
- Prometheus Operator only scrapes ServiceMonitors with this label
- Matches the Helm release name of kube-prometheus-stack

---

### 3. Backend Service Update

Updated service to include port name and labels for ServiceMonitor matching.

**File:** `todo/k8s/backend-service.yaml`

```yaml
# Before
ports:
  - port: 8080
    targetPort: 8080

# After
metadata:
  labels:
    app: todo-api
ports:
  - name: http        # Named port for ServiceMonitor
    port: 8080
    targetPort: 8080
```

---

### 4. MySQL ServiceMonitor

Created ServiceMonitor for MySQL exporter (already running as sidecar).

**File:** `todo/k8s/mysql-servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mysql
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: mysql
  namespaceSelector:
    matchNames:
      - testswilts
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

---

### 5. MySQL Service Update

Added metrics port for the mysqld-exporter sidecar.

**File:** `todo/k8s/mysql-service.yaml`

```yaml
# Before
ports:
  - port: 3306
    targetPort: 3306

# After
metadata:
  labels:
    app: mysql
ports:
  - name: mysql
    port: 3306
    targetPort: 3306
  - name: metrics       # Exporter port
    port: 9104
    targetPort: 9104
```

---

### 6. Grafana Dashboard

Created a ConfigMap with a pre-built Grafana dashboard.

**File:** `todo/k8s/grafana-dashboard-configmap.yaml`

**Dashboard Sections:**

| Section | Panels |
|---------|--------|
| **Todo API Overview** | API Latency (p95), Request Rate, Error Rate (5xx), Latency by Endpoint, Request Rate by Endpoint |
| **JVM Metrics** | Heap Memory Usage, JVM Threads (Live/Daemon) |
| **MySQL Database** | Connections, Queries/sec, Commands by Type (SELECT/INSERT/UPDATE/DELETE) |
| **Connection Pool** | HikariCP Active/Idle/Pending, Connection Acquire Time |

**How it works:**
- ConfigMap has label `grafana_dashboard: "1"`
- Grafana sidecar automatically discovers and loads dashboards with this label
- Dashboard appears in Grafana under "General" folder

---

### 7. Kustomization Update

Added all new resources to kustomization.

**File:** `todo/k8s/kustomization.yaml`

```yaml
resources:
  - secret.yaml
  - configmap.yaml
  - mysql-pvc.yaml
  - mysql-deployment.yaml
  - mysql-service.yaml
  - backend-deployment.yaml
  - backend-service.yaml
  - frontend-deployment.yaml
  - frontend-service.yaml
  - servicemonitor.yaml              # NEW
  - mysql-servicemonitor.yaml        # NEW
  - grafana-dashboard-configmap.yaml # NEW
```

---

### 8. Backend Image Update

Updated deployment to use v2 image with metrics enabled.

**File:** `todo/k8s/backend-deployment.yaml`

```yaml
# Before
image: hub.comcast.net/sandbox/todo-backend:latest

# After
image: hub.comcast.net/sandbox/todo-backend:v2
```

**Requires rebuilding:**
```bash
cd ~/Desktop/Flux_CI/todo/Backend
docker build --platform linux/amd64 -t hub.comcast.net/sandbox/todo-backend:v2 .
docker push hub.comcast.net/sandbox/todo-backend:v2
```

---

## Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `todo/Backend/pom.xml` | Modified | Added Actuator + Micrometer dependencies |
| `todo/Backend/src/main/resources/application.properties` | Modified | Enabled Prometheus endpoint |
| `todo/k8s/servicemonitor.yaml` | Created | Prometheus scrape config for backend |
| `todo/k8s/mysql-servicemonitor.yaml` | Created | Prometheus scrape config for MySQL |
| `todo/k8s/backend-service.yaml` | Modified | Added labels and port name |
| `todo/k8s/mysql-service.yaml` | Modified | Added labels and metrics port |
| `todo/k8s/grafana-dashboard-configmap.yaml` | Created | Pre-built Grafana dashboard |
| `todo/k8s/kustomization.yaml` | Modified | Added new resources |
| `todo/k8s/backend-deployment.yaml` | Modified | Updated to v2 image |

---

## Verification Commands

### Check ServiceMonitors
```bash
kubectl get servicemonitors -A
```

### Verify Prometheus Targets
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets
# Look for "testswilts/todo-api" and "testswilts/mysql"
```

### Test Metrics Endpoint
```bash
kubectl port-forward svc/todo-api 8080:8080 -n testswilts
curl http://localhost:8080/actuator/prometheus
```

### Access Grafana Dashboard
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# Search for "Todo App Dashboard"
```

### Get Grafana Password
```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

---

## Key Metrics Available

### Backend API
| Metric | Description |
|--------|-------------|
| `http_server_requests_seconds_count` | Total request count |
| `http_server_requests_seconds_sum` | Total request duration |
| `http_server_requests_seconds_bucket` | Latency histogram |

### JVM
| Metric | Description |
|--------|-------------|
| `jvm_memory_used_bytes` | Memory usage by area |
| `jvm_memory_max_bytes` | Max memory by area |
| `jvm_threads_live_threads` | Current thread count |
| `jvm_gc_pause_seconds` | GC pause duration |

### HikariCP (Connection Pool)
| Metric | Description |
|--------|-------------|
| `hikaricp_connections_active` | Active connections |
| `hikaricp_connections_idle` | Idle connections |
| `hikaricp_connections_pending` | Waiting for connection |

### MySQL
| Metric | Description |
|--------|-------------|
| `mysql_global_status_threads_connected` | Current connections |
| `mysql_global_status_queries` | Total queries executed |
| `mysql_global_status_commands_total` | Commands by type |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CNAP Cluster                             │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  Frontend   │───▶│  Backend    │───▶│   MySQL     │     │
│  │  (Go)       │    │  (Spring)   │    │  + Exporter │     │
│  └─────────────┘    └──────┬──────┘    └──────┬──────┘     │
│                            │                   │            │
│                     /actuator/prometheus  /metrics:9104     │
│                            │                   │            │
│                            ▼                   ▼            │
│                    ┌───────────────────────────────┐        │
│                    │       Prometheus              │        │
│                    │   (ServiceMonitor scrape)     │        │
│                    └───────────────┬───────────────┘        │
│                                    │                        │
│                                    ▼                        │
│                    ┌───────────────────────────────┐        │
│                    │         Grafana               │        │
│                    │   (Todo App Dashboard)        │        │
│                    └───────────────────────────────┘        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### Metrics not appearing in Prometheus

1. Check ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor todo-api -n testswilts
   ```

2. Verify label matches:
   ```bash
   kubectl get svc todo-api -n testswilts --show-labels
   ```

3. Check Prometheus targets:
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   # Visit http://localhost:9090/targets
   ```

### Dashboard not appearing in Grafana

1. Check ConfigMap exists:
   ```bash
   kubectl get configmap todo-app-dashboard -n monitoring
   ```

2. Verify label:
   ```bash
   kubectl get configmap todo-app-dashboard -n monitoring --show-labels
   # Should have: grafana_dashboard=1
   ```

3. Restart Grafana to reload dashboards:
   ```bash
   kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
   ```

### Backend metrics endpoint returns 404

1. Verify Actuator is enabled in `application.properties`
2. Ensure backend was rebuilt with new dependencies
3. Check pod is running latest image:
   ```bash
   kubectl describe pod -l app=todo-api -n testswilts | grep Image
   ```
