#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="9.4.17"

echo "==> Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

echo "==> Creating namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" 2>/dev/null || true

echo "==> Installing Argo CD (chart v${ARGOCD_CHART_VERSION}) — initial bootstrap..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGOCD_NAMESPACE}" \
  --version "${ARGOCD_CHART_VERSION}" \
  --set server.extraArgs[0]="--insecure" \
  --set configs.params."server\.insecure"=true \
  --wait \
  --timeout 5m

echo "==> Waiting for argocd-server to be ready..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NAMESPACE}" \
  --timeout=180s

echo "==> Argo CD bootstrap complete."
echo ""
echo "    Admin password: kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
