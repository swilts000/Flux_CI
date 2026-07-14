#!/bin/bash
set -e

NAMESPACES=("testswilts" "flux-system" "metacontroller")
MONITORING="monitoring"  
FAILED=0                

GREEN='\033[0;32m'   
RED='\033[0;31m'     
YELLOW='\033[1;33m'  
NC='\033[0m'         

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Multi-Namespace Health Check${NC}"
echo -e "${YELLOW}  App Namespaces: ${NAMESPACES[*]}${NC}"
echo -e "${YELLOW}  Monitoring: ${MONITORING}${NC}"
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
echo "══════════════════════════════════════════════════════════════════════════════"
printf "%-20s %-10s %-10s %-10s\n" "NAMESPACE" "RUNNING" "PENDING" "FAILED"
printf "%-20s %-10s %-10s %-10s\n" "────────────────────" "──────────" "──────────" "──────────"

for NS in "${NAMESPACES[@]}"; do
    PODS_OUTPUT=$(kubectl get pods -n $NS --no-headers 2>/dev/null)
    if [ -z "$PODS_OUTPUT" ]; then
        RUNNING=0; PENDING=0; FAILED_PODS=0
    else
        RUNNING=$(echo "$PODS_OUTPUT" | grep -c "Running" || true)
        PENDING=$(echo "$PODS_OUTPUT" | grep -c "Pending" || true)
        FAILED_PODS=$(echo "$PODS_OUTPUT" | grep -cE "Error|CrashLoopBackOff|Failed" || true)
    fi
    printf "%-20s %-10d %-10d %-10d\n" "$NS" "$RUNNING" "$PENDING" "$FAILED_PODS"
    [ "$RUNNING" -ge 1 ]
    check "${NS}: has running pods"
done

PODS_OUTPUT=$(kubectl get pods -n $MONITORING --no-headers 2>/dev/null)
if [ -z "$PODS_OUTPUT" ]; then
    RUNNING=0; PENDING=0; FAILED_PODS=0
else
    RUNNING=$(echo "$PODS_OUTPUT" | grep -c "Running" || true)
    PENDING=$(echo "$PODS_OUTPUT" | grep -c "Pending" || true)
    FAILED_PODS=$(echo "$PODS_OUTPUT" | grep -cE "Error|CrashLoopBackOff|Failed" || true)
fi
printf "%-20s %-10d %-10d %-10d\n" "$MONITORING" "$RUNNING" "$PENDING" "$FAILED_PODS"
[ "$RUNNING" -ge 4 ]
check "${MONITORING}: has 4+ running pods"

echo -e "\n${YELLOW}[2/6] Service Endpoints${NC}"
echo "────────────────────────────────────────"

for NS in "${NAMESPACES[@]}"; do
    SERVICES=$(kubectl get svc -n $NS --no-headers 2>/dev/null | awk '{print $1}')
    for SVC in $SERVICES; do
        kubectl get endpoints $SVC -n $NS -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
        check "${NS}/${SVC} has endpoints"
    done
done

kubectl get endpoints kube-prometheus-stack-prometheus -n $MONITORING -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "prometheus service has endpoints"

kubectl get endpoints kube-prometheus-stack-grafana -n $MONITORING -o jsonpath='{.subsets[0].addresses[0].ip}' &>/dev/null
check "grafana service has endpoints"

echo -e "\n${YELLOW}[3/6] Cross-Namespace DNS Resolution${NC}"
echo "────────────────────────────────────────"

for NS in "${NAMESPACES[@]}"; do
    FIRST_SVC=$(kubectl get svc -n $NS --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$FIRST_SVC" ]; then
        kubectl run dns-test-${NS} --image=busybox:1.36 --rm -it --restart=Never -n $MONITORING \
          --command -- nslookup ${FIRST_SVC}.${NS}.svc.cluster.local &>/dev/null
        check "DNS: ${MONITORING} → ${FIRST_SVC}.${NS}"
    fi
done

echo -e "\n${YELLOW}[4/6] ServiceMonitors${NC}"
echo "────────────────────────────────────────"

for NS in "${NAMESPACES[@]}"; do
    SM_LIST=$(kubectl get servicemonitors -n $NS --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [ -z "$SM_LIST" ]; then
        echo -e "${YELLOW}  No ServiceMonitors in ${NS}${NC}"
    else
        for SM in $SM_LIST; do
            kubectl get servicemonitor $SM -n $NS &>/dev/null
            check "ServiceMonitor: ${NS}/${SM}"
        done
    fi
done

echo -e "\n${YELLOW}[5/6] Metrics Endpoints${NC}"
echo "────────────────────────────────────────"

for NS in "${NAMESPACES[@]}"; do
    DEPLOYMENTS=$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{print $1}')
    for DEPLOY in $DEPLOYMENTS; do
        METRICS_PATH="/actuator/prometheus"
        kubectl exec -n $NS deploy/$DEPLOY -- wget -qO- http://localhost:8080${METRICS_PATH} 2>/dev/null | head -1 | grep -q "#" && \
            check "${NS}/${DEPLOY} exposes metrics" || \
            echo -e "${YELLOW}  ${NS}/${DEPLOY} - no metrics endpoint${NC}"
    done
done

echo -e "\n${YELLOW}[6/6] Flux GitOps Status${NC}"
echo "────────────────────────────────────────"

flux get kustomization flux-system 2>/dev/null | grep -q "True"
check "Flux kustomization: flux-system is Ready"

for NS in "${NAMESPACES[@]}"; do
    KUST_NAME=$(flux get kustomization -A 2>/dev/null | grep -i $NS | awk '{print $2}' | head -1)
    if [ -n "$KUST_NAME" ]; then
        flux get kustomization $KUST_NAME 2>/dev/null | grep -q "True"
        check "Flux kustomization: ${KUST_NAME} is Ready"
    fi
done

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
