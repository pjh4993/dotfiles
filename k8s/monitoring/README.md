# Local Monitoring (kube-prometheus-stack)

Prometheus + Grafana + node-exporter + kube-state-metrics for Docker Desktop Kubernetes.
This directory is **not** a chart — it's a values file + installer that drives the upstream
[`prometheus-community/kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

## Install

```bash
./start.sh
```

That runs `helm repo add prometheus-community ...` and:

```bash
helm upgrade --install kube-prom-stack \
  prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f values.yaml
```

## Access Grafana

Add to `/etc/hosts` (one-time, requires sudo):

```
127.0.0.1 grafana.jhpark.local
```

Then open <http://grafana.jhpark.local> — login `admin` / `admin`.

Built-in dashboards under **Dashboards → Browse** include:
- *Kubernetes / Compute Resources / Pod* — per-pod CPU and memory
- *Kubernetes / Compute Resources / Namespace (Pods)*
- *Kubernetes / Compute Resources / Node (Pods)*
- *Node Exporter / Nodes*

## Upgrade after changing values.yaml

```bash
./start.sh
```

## Uninstall

```bash
helm uninstall kube-prom-stack -n monitoring
# Wipe storage too:
kubectl delete namespace monitoring
```

## Notes on this configuration

- **Lean footprint:** Alertmanager disabled, Prometheus retention 3d / 4 GB, lower resource requests.
- **Docker Desktop quirk:** `kubeControllerManager`, `kubeScheduler`, `kubeProxy`, and `kubeEtcd`
  endpoints are not reachable on Docker Desktop k8s, so those ServiceMonitors are disabled to
  silence persistent scrape errors. Pod metrics still come from cAdvisor via the kubelet.
- **Storage:** uses the `hostpath` default StorageClass.
- **Ingress:** routes through your existing `ingress-nginx`.
