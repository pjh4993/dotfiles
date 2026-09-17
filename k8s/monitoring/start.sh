#!/bin/bash
# Installs/upgrades kube-prometheus-stack into the `monitoring` namespace
# with overrides from this directory's values.yaml.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

CHART_REPO="prometheus-community"
CHART_NAME="kube-prometheus-stack"
RELEASE="kube-prom-stack"
NAMESPACE="monitoring"
VALUES="$(cd "$(dirname "$0")" && pwd)/values.yaml"

echo "[monitoring] Ensuring helm repo..."
helm repo add "$CHART_REPO" https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update "$CHART_REPO" >/dev/null

echo "[monitoring] Waiting for Kubernetes..."
until kubectl cluster-info &>/dev/null 2>&1; do
    sleep 5
done

echo "[monitoring] Deploying $RELEASE → ns/$NAMESPACE ..."
helm upgrade --install "$RELEASE" "$CHART_REPO/$CHART_NAME" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES"

echo "[monitoring] Done."
echo "    Grafana: http://grafana.jhpark.local  (admin/admin)"
echo "    Ensure /etc/hosts has: 127.0.0.1 grafana.jhpark.local"
