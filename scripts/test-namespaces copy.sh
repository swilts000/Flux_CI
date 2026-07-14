#!/bin/bash
# =============================================================================
# test-namespaces.sh
# =============================================================================
# Description: Comprehensive health check script for testswilts and monitoring
#              namespaces. Tests pod health, service endpoints, DNS resolution,
#              ServiceMonitors, metrics endpoints, and Flux GitOps status.
#
# Usage:       ./scripts/test-namespaces.sh
#
# Exit Codes:  0 = All tests passed
#              N = Number of failed tests
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - flux CLI installed
#   - Cluster has testswilts and monitoring namespaces deployed
# =============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# =============================================================================
# Global Variables
# =============================================================================
SPACE="testswilts"       # Target namespace for the todo application
MONITORING="monitoring"  # Target namespace for Prometheus/Grafana stack
FAILED=0                 # Counter for failed tests - used as exit code

# =============================================================================
# Color Definitions
# =============================================================================
# ANSI color codes for terminal output formatting
GREEN='\033[0;32m'   # Success messages
RED='\033[0;31m'     # Failure messages
YELLOW='\033[1;33m'  # Section headers and warnings
NC='\033[0m'         # No Color - reset to default

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Namespace Health Check: ${SPACE} & ${MONITORING}${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
# Helper Functions
# =============================================================================

# check()
# -------
# Evaluates the exit status of the previous command and prints pass/fail.
# Increments FAILED counter on failure.
#
# Arguments:
#   $1 - Description of the test being checked
#
# Usage:
#   some_command
#   check "Description of what was tested"
check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        FAILED=$((FAILED + 1))
    fi
}

# =============================================================================
# SECTION 1: Pod Health
# =============================================================================
# Verifies that the expected number of pods are in "Running" state.
# - testswilts: Expects at least 3 pods (todo-api, todo-frontend, mysql)
# - monitoring: Expects at least 4 pods (prometheus, grafana, alertmanager, operator)
# =============================================================================
echo -e "\n${YELLOW}[1/6] Pod Health${NC}"
echo "────────────────────────────────────────"

# Count running pods in testswilts namespace
# grep -c counts matching lines; || echo 0 handles case where no pods exist
TESTSWILTS_PODS=$(kubectl get pods -n $SPACE --no-headers 2>/dev/null | grep -c "Running" || echo 0)
[ "$TESTSWILTS_PODS" -ge 3 ]
check "${SPACE}: $TESTSWILTS_PODS pods running (expected: 3+)"

# Count running pods in monitoring namespace
MONITORING_PODS=$(kubectl get pods -n $MONITORING --no-headers 2>/dev/null | grep -c "Running" || echo 0)
[ "$MONITORING_PODS" -ge 4 ]
check "${MONITORING}: $MONITORING_PODS pods running (expected: 4+)"

# =============================================================================
# SECTION 2: Service Endpoints
# =============================================================================
# Verifies that Kubernetes Services have backing Endpoints (pods).
# A service without endpoints means no pods match its selector, or pods aren't ready.
# Uses jsonpath to extract the first endpoint IP - if it exists, service is healthy.
# =============================================================================
echo -e "\n${YELLOW}[2/6] Service Endpoints${NC}"
echo "────────────────────────────────────────"

# Check testswilts services have endpoints
# jsonpath extracts first IP from endpoints; if empty, service has no backing pods
kubectl get endpoints todo-api -n $SPACE -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "todo-api service has endpoints"

kubectl get endpoints todo-frontend -n $SPACE -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "todo-frontend service has endpoints"

kubectl get endpoints mysql -n $SPACE -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "mysql service has endpoints"

# Check monitoring services have endpoints
kubectl get endpoints kube-prometheus-stack-prometheus -n $MONITORING -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "prometheus service has endpoints"

kubectl get endpoints kube-prometheus-stack-grafana -n $MONITORING -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "grafana service has endpoints"

# =============================================================================
# SECTION 3: Cross-Namespace DNS Resolution
# =============================================================================
# Tests that Kubernetes DNS resolves service names across namespaces.
# This is critical for Prometheus (in monitoring) to scrape metrics from
# todo-api (in testswilts). Uses temporary busybox pods to run nslookup.
#
# DNS Format: <service>.<namespace>.svc.cluster.local
# =============================================================================
echo -e "\n${YELLOW}[3/6] Cross-Namespace DNS Resolution${NC}"
echo "────────────────────────────────────────"

# Test DNS resolution from monitoring namespace to testswilts namespace
# Creates a temporary busybox pod, runs nslookup, then auto-deletes (--rm)
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -n $MONITORING \
  --command -- nslookup todo-api.${SPACE}.svc.cluster.local &>/dev/null
check "DNS: ${MONITORING} → todo-api.${SPACE}"

# Test DNS resolution from testswilts namespace to monitoring namespace
kubectl run dns-test2 --image=busybox:1.36 --rm -it --restart=Never -n $SPACE \
  --command -- nslookup kube-prometheus-stack-prometheus.${MONITORING}.svc.cluster.local &>/dev/null
check "DNS: ${SPACE} → prometheus.${MONITORING}"

# =============================================================================
# SECTION 4: ServiceMonitors
# =============================================================================
# Verifies that ServiceMonitor CRDs exist for Prometheus to discover scrape targets.
# ServiceMonitors tell Prometheus Operator which services to scrape and how.
# Without these, Prometheus won't know to collect metrics from our apps.
# =============================================================================
echo -e "\n${YELLOW}[4/6] ServiceMonitors${NC}"
echo "────────────────────────────────────────"

# Check if todo-api ServiceMonitor exists (scrapes /actuator/prometheus)
kubectl get servicemonitor todo-api -n $SPACE &>/dev/null
check "ServiceMonitor: todo-api exists"

# Check if mysql ServiceMonitor exists (scrapes mysqld-exporter on :9104)
kubectl get servicemonitor mysql -n $SPACE &>/dev/null
check "ServiceMonitor: mysql exists"

# =============================================================================
# SECTION 5: Metrics Endpoints
# =============================================================================
# Tests that applications expose metrics endpoints and they're accessible.
# - First test: Checks todo-api health endpoint from within its own pod
# - Second test: Simulates Prometheus by calling metrics endpoint from monitoring ns
# =============================================================================
echo -e "\n${YELLOW}[5/6] Metrics Endpoints (via kubectl exec)${NC}"
echo "────────────────────────────────────────"

# Test todo-api health endpoint from within the pod itself
# Uses wget (available in most containers) to call localhost:8080/actuator/health
# Expects response containing "UP" indicating Spring Boot app is healthy
kubectl exec -n $SPACE deploy/todo-api -- wget -qO- http://localhost:8080/actuator/health 2>/dev/null | grep -q "UP"
check "todo-api /actuator/health returns UP"

# Test cross-namespace metrics access (simulates what Prometheus does)
# Creates a temporary curl pod in monitoring namespace and calls todo-api in testswilts
# Prometheus metrics start with "#" (comments) so we check for that
kubectl run metrics-test --image=curlimages/curl:8.5.0 --rm -it --restart=Never -n $MONITORING \
  --command -- curl -s http://todo-api.${SPACE}.svc.cluster.local:8080/actuator/prometheus 2>/dev/null | head -1 | grep -q "#"
check "Prometheus can reach todo-api metrics endpoint"

# =============================================================================
# SECTION 6: Flux GitOps Status
# =============================================================================
# Verifies that Flux GitOps is properly syncing resources from Git repository.
# - Kustomizations: Define what manifests to apply from Git
# - HelmReleases: Define Helm charts to install (like kube-prometheus-stack)
# "True" in output indicates the resource is successfully reconciled
# =============================================================================
echo -e "\n${YELLOW}[6/6] Flux GitOps Status${NC}"
echo "────────────────────────────────────────"

# Check flux-system kustomization (the root Flux configuration)
flux get kustomization flux-system 2>/dev/null | grep -q "True"
check "Flux kustomization: flux-system is Ready"

# Check todo-app kustomization (deploys our todo application)
flux get kustomization todo-app 2>/dev/null | grep -q "True"
check "Flux kustomization: todo-app is Ready"

# Check kube-prometheus-stack HelmRelease (deploys Prometheus/Grafana)
flux get helmrelease -n $MONITORING kube-prometheus-stack 2>/dev/null | grep -q "True"
check "HelmRelease: kube-prometheus-stack is Ready"

# =============================================================================
# SUMMARY
# =============================================================================
# Prints final test results and exits with the number of failed tests.
# Exit code 0 = all tests passed, can be used in CI/CD pipelines.
# =============================================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
else
    echo -e "${RED}$FAILED test(s) failed${NC}"
fi
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

# Exit with number of failures (0 = success for CI/CD)
exit $FAILED
