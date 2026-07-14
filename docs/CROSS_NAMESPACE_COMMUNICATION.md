# Cross-Namespace Communication: testswilts ↔ monitoring

This document explains how Prometheus in the `monitoring` namespace communicates with and scrapes metrics from the Todo app in the `testswilts` namespace.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CNAP Cluster                                    │
│                                                                         │
│  ┌─────────────────────────────┐    ┌─────────────────────────────┐    │
│  │     testswilts namespace    │    │     monitoring namespace    │    │
│  │                             │    │                             │    │
│  │  ┌─────────┐  ┌─────────┐  │    │  ┌─────────────────────┐   │    │
│  │  │ todo-api│  │  mysql  │  │    │  │     Prometheus      │   │    │
│  │  │ :8080   │  │  :9104  │  │◄───┼──│  (scrapes metrics)  │   │    │
│  │  └────┬────┘  └────┬────┘  │    │  └─────────────────────┘   │    │
│  │       │            │       │    │             │               │    │
│  │  /actuator/    /metrics    │    │             ▼               │    │
│  │  prometheus                │    │  ┌─────────────────────┐   │    │
│  │                            │    │  │      Grafana        │   │    │
│  │  ┌─────────────────────┐  │    │  │  (visualizes data)  │   │    │
│  │  │   ServiceMonitor    │──┼────┼─▶│                     │   │    │
│  │  │ (tells Prometheus   │  │    │  └─────────────────────┘   │    │
│  │  │  what to scrape)    │  │    │                             │    │
│  │  └─────────────────────┘  │    │                             │    │
│  └─────────────────────────────┘    └─────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Communication Flow

### Step 1: ServiceMonitor Discovery

ServiceMonitor is a Custom Resource that tells Prometheus what to scrape.

**Your ServiceMonitor** (`testswilts/todo-api`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: todo-api
  namespace: testswilts
  labels:
    release: kube-prometheus-stack  # Prometheus looks for this label
spec:
  selector:
    matchLabels:
      app: todo-api                 # Finds services with this label
  namespaceSelector:
    matchNames:
      - testswilts                  # In this namespace
  endpoints:
    - port: http                    # Scrape this port
      path: /actuator/prometheus    # At this path
      interval: 30s                 # Every 30 seconds
```

**How Prometheus finds it:**

1. Prometheus Operator watches for ServiceMonitors with label `release: kube-prometheus-stack`
2. It finds your ServiceMonitor in `testswilts` namespace
3. It generates scrape config and reloads Prometheus

---

### Step 2: Kubernetes DNS Resolution

Kubernetes provides internal DNS so pods can find services across namespaces.

**DNS Format:**

```
<service-name>.<namespace>.svc.cluster.local
```

**Example:**

Prometheus (in `monitoring`) calls:

```
http://todo-api.testswilts.svc.cluster.local:8080/actuator/prometheus
```

Kubernetes DNS resolves this to the `todo-api` Service's ClusterIP, and traffic routes to the `todo-api` pod.

---

### Step 3: Network Policy (Default: Allow All)

By default, Kubernetes allows all pod-to-pod communication across namespaces.

**Your cluster:** No NetworkPolicies blocking traffic, so:

- `monitoring/prometheus` → `testswilts/todo-api` ✅ Allowed
- `monitoring/prometheus` → `testswilts/mysql` ✅ Allowed

---

### Step 4: Metrics Scraping

**What happens every 30 seconds:**

1. **Prometheus** sends HTTP GET request:

   ```
   GET http://todo-api.testswilts.svc.cluster.local:8080/actuator/prometheus
   ```

2. **todo-api** responds with metrics:

   ```
   # HELP http_server_requests_seconds Duration of HTTP server request handling
   # TYPE http_server_requests_seconds histogram
   http_server_requests_seconds_bucket{method="GET",uri="/api/todos",le="0.001"} 5
   http_server_requests_seconds_bucket{method="GET",uri="/api/todos",le="0.005"} 12
   ...
   jvm_memory_used_bytes{area="heap",id="G1 Eden Space"} 12345678
   ```

3. **Prometheus** stores these metrics in its time-series database

4. **Grafana** queries Prometheus and displays dashboards

---

## Verification Commands

### Check 1: Prometheus Targets UI

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Open http://localhost:9090/targets
```

**What you'll see:**

| Endpoint | State | Labels |
|----------|-------|--------|
| `http://10.244.1.5:8080/actuator/prometheus` | **UP** | `namespace="testswilts"` |
| `http://10.244.1.6:9104/metrics` | **UP** | `namespace="testswilts"` |

- **UP** = Prometheus successfully scraped metrics
- **DOWN** = Connection failed (network issue, wrong port, app not exposing metrics)

---

### Check 2: Query Metrics

In Prometheus UI, run:

```promql
up{namespace="testswilts"}
```

**Result:**

```
up{instance="10.244.1.5:8080", job="testswilts/todo-api", namespace="testswilts"} 1
up{instance="10.244.1.6:9104", job="testswilts/mysql", namespace="testswilts"} 1
```

- `1` = Target is up and being scraped
- `0` = Target is down

---

### Check 3: Direct Network Test

```bash
kubectl exec -it -n monitoring deploy/kube-prometheus-stack-operator -- \
  wget -qO- http://todo-api.testswilts.svc.cluster.local:8080/actuator/prometheus | head -20
```

**What this does:**

1. Exec into a pod in `monitoring` namespace
2. Make HTTP request to `todo-api` in `testswilts` namespace
3. If metrics return, cross-namespace communication works

**Expected output:**

```
# HELP jvm_memory_used_bytes The amount of used memory
# TYPE jvm_memory_used_bytes gauge
jvm_memory_used_bytes{area="heap",id="G1 Eden Space"} 1.2345678E7
...
```

---

### Check 4: View ServiceMonitors

```bash
kubectl get servicemonitors -n testswilts
```

Expected output:

```
NAME       AGE
todo-api   1h
mysql      1h
```

---

### Check 5: Prometheus Scrape Config

```bash
kubectl get secret -n monitoring prometheus-kube-prometheus-stack-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep testswilts
```

If `testswilts` appears in the config, Prometheus knows to scrape it.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Target shows **DOWN** | App not exposing metrics | Check `/actuator/prometheus` endpoint |
| Target not appearing | ServiceMonitor label mismatch | Verify `release: kube-prometheus-stack` label |
| Connection refused | Wrong port in ServiceMonitor | Check service port name matches |
| No route to host | NetworkPolicy blocking | Check for restrictive NetworkPolicies |
| DNS resolution failed | Service doesn't exist | Verify service name and namespace |

---

## Component Summary

| Component | Role | Namespace |
|-----------|------|-----------|
| **todo-api** | Exposes metrics at `/actuator/prometheus` | testswilts |
| **mysql-exporter** | Exposes MySQL metrics at `/metrics:9104` | testswilts |
| **ServiceMonitor** | Tells Prometheus what/where to scrape | testswilts |
| **Prometheus** | Scrapes metrics every 30s | monitoring |
| **Grafana** | Visualizes metrics | monitoring |

---

## Key Enablers

1. **Kubernetes DNS** - Allows cross-namespace service discovery
2. **ServiceMonitor** - Configures Prometheus scrape targets
3. **No NetworkPolicies** - Default allows all traffic

---

## Related Documentation

- [DEPLOYMENT_FIXES.md](./DEPLOYMENT_FIXES.md) - Initial deployment issues and fixes
- [MONITORING_SETUP.md](./MONITORING_SETUP.md) - Monitoring configuration details
