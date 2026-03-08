# Local Dev Infrastructure (Helm Chart)

PostgreSQL, RabbitMQ, and Redis packaged as a Helm chart (`dev-infra`) for Docker Desktop Kubernetes.

## Startup (auto-deploy on login)

A launchd agent is included to deploy the chart automatically when you log in.

```bash
# Install (one-time)
stow -t ~ launchagents
launchctl load ~/Library/LaunchAgents/com.pyler.dev-infra.plist

# Logs
tail -f ~/Library/Logs/dev-infra.log

# Stop / disable
launchctl unload ~/Library/LaunchAgents/com.pyler.dev-infra.plist
```

## Prerequisites

- Enable Kubernetes in Docker Desktop → Settings → Kubernetes → Enable Kubernetes
- [Helm](https://helm.sh/docs/intro/install/) installed

## Usage

```bash
# Install (creates namespace + all resources)
helm install dev-infra ./k8s

# Upgrade after values change
helm upgrade dev-infra ./k8s

# Check status
kubectl get pods -n dev

# Uninstall (keeps PVCs/data)
helm uninstall dev-infra

# Wipe data too
kubectl delete namespace dev
```

## Customization

Override any value from `values.yaml` at install time:

```bash
helm install dev-infra ./k8s \
  --set postgres.password=secret \
  --set postgres.storage=5Gi \
  --set namespace=staging
```

Or provide a custom values file:

```bash
helm install dev-infra ./k8s -f my-values.yaml
```

## Connection Details

| Service    | Host      | Port  | Notes                            |
|------------|-----------|-------|----------------------------------|
| PostgreSQL | localhost | 5432  | user: dev / pass: dev / db: mydb |
| RabbitMQ   | localhost | 5672  | user: dev / pass: dev (AMQP)    |
| RabbitMQ   | localhost | 15672 | Management UI                    |
| Redis      | localhost | 6379  | No auth                          |

## In-cluster connection (from other pods in `dev` namespace)

| Service    | Host     | Port |
|------------|----------|------|
| PostgreSQL | postgres | 5432 |
| RabbitMQ   | rabbitmq | 5672 |
| Redis      | redis    | 6379 |
