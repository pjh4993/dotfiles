#!/bin/bash
# Waits for Docker Desktop Kubernetes to be ready, then deploys dev-infra.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "[dev-infra] Waiting for Kubernetes..."
until kubectl cluster-info &>/dev/null 2>&1; do
    sleep 5
done

echo "[dev-infra] Kubernetes ready. Deploying..."
helm upgrade --install dev-infra "$HOME/dotfiles/k8s"
echo "[dev-infra] Done."
