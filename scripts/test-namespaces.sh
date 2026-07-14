#!/bin/bash
set -e

SPACE="testswilts"        
MONITORING="monitoring"  
FAILED=0                

GREEN='\033[0;32m'   
RED='\033[0;31m'     
YELLOW='\033[1;33m'  
NC='\033[0m'         

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Namespace Health Check: ${SPACE} & ${MONITORING}${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""


check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        FAILED=$((FAILED + 1))
    fi
}

echo -e "\n${YELLOW}[1/6] Pod Health${NC}"
echo "────────────────────────────────────────"

TESTSWILTS_PODS=$(kubectl get pods -n $SPACE --no-headers 2>/dev/null | grep -c "Running" || echo 0)
[ "$TESTSWILTS_PODS" -ge 3 ]
check "${SPACE}: $TESTSWILTS_PODS pods running (expected: 3+)"

MONITORING_PODS=$(kubectl get pods -n $MONITORING --no-headers 2>/dev/null | grep -c "Running" || echo 0)
[ "$MONITORING_PODS" -ge 4 ]
check "${MONITORING}: $MONITORING_PODS pods running (expected: 4+)"

echo -e "\n${YELLOW}[2/6] Service Endpoints${NC}"
echo "────────────────────────────────────────"

kubectl get endpoints todo-api -n $SPACE -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "todo-api service has endpoints"

kubectl get endpoints todo-frontend -n $SPACE -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "todo-frontend service has endpoints"

kubectl get endpoints mysql -n $SPACE -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "mysql service has endpoints"

kubectl get endpoints kube-prometheus-stack-prometheus -n $MONITORING -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "prometheus service has endpoints"

kubectl get endpoints kube-prometheus-stack-grafana -n $MONITORING -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "grafana service has endpoints"

echo -e "\n${YELLOW}[3/6] Cross-Namespace DNS Resolution${NC}"
echo "────────────────────────────────────────"

kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -n $MONITORING \
  --command -- nslookup todo-api.${SPACE}.svc.cluster.local &>/dev/null
check "DNS: ${MONITORING} → todo-api.${SPACE}"

kubectl run dns-test2 --image=busybox:1.36 --rm -it --restart=Never -n $SPACE \
  --command -- nslookup kube-prometheus-stack-prometheus.${MONITORING}.svc.cluster.local &>/dev/null
check "DNS: ${SPACE} → prometheus.${MONITORING}"

echo -e "\n${YELLOW}[4/6] ServiceMonitors${NC}"
echo "────────────────────────────────────────"

kubectl get servicemonitor todo-api -n $SPACE &>/dev/null
check "ServiceMonitor: todo-api exists"

kubectl get servicemonitor mysql -n $SPACE &>/dev/null
check "ServiceMonitor: mysql exists"

echo -e "\n${YELLOW}[5/6] Metrics Endpoints (via kubectl exec)${NC}"
echo "────────────────────────────────────────"

kubectl exec -n $SPACE deploy/todo-api -- wget -qO- http://localhost:8080/actuator/health 2>/dev/null | grep -q "UP"
check "todo-api /actuator/health returns UP"

kubectl run metrics-test --image=curlimages/curl:8.5.0 --rm -it --restart=Never -n $MONITORING \
  --command -- curl -s http://todo-api.${SPACE}.svc.cluster.local:8080/actuator/prometheus 2>/dev/null | head -1 | grep -q "#"
check "Prometheus can reach todo-api metrics endpoint"

echo -e "\n${YELLOW}[6/6] Flux GitOps Status${NC}"
echo "────────────────────────────────────────"

flux get kustomization flux-system 2>/dev/null | grep -q "True"
check "Flux kustomization: flux-system is Ready"

flux get kustomization todo-app 2>/dev/null | grep -q "True"
check "Flux kustomization: todo-app is Ready"

flux get helmrelease -n $MONITORING kube-prometheus-stack 2>/dev/null | grep -q "True"
check "HelmRelease: kube-prometheus-stack is Ready"

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
else
    echo -e "${RED}$FAILED test(s) failed${NC}"
fi
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

exit $FAILED
