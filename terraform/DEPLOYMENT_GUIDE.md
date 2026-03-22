# Kubernetes Deployment Guide for Enterprise

This guide walks through deploying the Payments Streaming Platform to AKS with production-grade configurations suitable for regulated financial institutions.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Resource Group                      │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │          AKS Cluster (Kubernetes)                     │   │
│  ├──────────────────────────────────────────────────────┤   │
│  │  Namespace: txn-analytics                             │   │
│  │  ┌─────────────────────────────────────────────┐     │   │
│  │  │  Flink JobManager (1 replica)                │     │   │
│  │  │  Flink TaskManagers (2 replicas, scalable)   │     │   │
│  │  │  Producer (1 replica)                        │     │   │
│  │  │  Consumer (1-5 replicas, HPA enabled)        │     │   │
│  │  │  API (3-10 replicas, HPA enabled)            │     │   │
│  │  │  Dashboard (1 replica)                       │     │   │
│  │  └─────────────────────────────────────────────┘     │   │
│  │  ┌─────────────────────────────────────────────┐     │   │
│  │  │  Stateful Services (Helm deployed)          │     │   │
│  │  │  Kafka (3 replicas + Zookeeper)             │     │   │
│  │  │  MongoDB (3 replicas + Arbiter)             │     │   │
│  │  └─────────────────────────────────────────────┘     │   │
│  │  ┌─────────────────────────────────────────────┐     │   │
│  │  │  Persistent Volumes (Premium SSD)           │     │   │
│  │  │  - Kafka data (20 Gi)                       │     │   │
│  │  │  - Zookeeper data (10 Gi)                   │     │   │
│  │  │  - MongoDB data (50 Gi)                     │     │   │
│  │  └─────────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Azure Container Registry (ACR)                      │   │
│  │  - All application images stored securely            │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Pre-Deployment Checklist

- [ ] Azure subscription with appropriate quotas
- [ ] User has AKS cluster creation permissions
- [ ] Docker installed locally for building images
- [ ] All app code tested on your local Docker Compose setup
- [ ] Network security policies reviewed
- [ ] Backup/disaster recovery strategy defined

## Detailed Deployment Steps

### 1. Prepare Application Images

Your application must be containerized. Build images for each component:

```bash
cd /home/james/payments-streaming-platform

# Build all docker images
docker build -f infra/Dockerfile.producer -t payments-producer:1.0 .
docker build -f infra/Dockerfile.consumer -t payments-consumer:1.0 .
docker build -f infra/Dockerfile.api -t payments-api:1.0 .
docker build -f infra/Dockerfile.dashboard -t payments-dashboard:1.0 .
docker build -f infra/Dockerfile.flink -t payments-flink:1.0 .

# Verify images
docker images | grep payments
```

### 2. Deploy to Azure Container Registry

```bash
# Get ACR details from terraform output
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
ACR_USERNAME=$(terraform output -raw acr_admin_username)

# Login to Azure
az acr login --name txnregistrydev

# Tag images for ACR
docker tag payments-producer:1.0 $ACR_LOGIN_SERVER/producer:1.0
docker tag payments-consumer:1.0 $ACR_LOGIN_SERVER/consumer:1.0
docker tag payments-api:1.0 $ACR_LOGIN_SERVER/api:1.0
docker tag payments-dashboard:1.0 $ACR_LOGIN_SERVER/dashboard:1.0
docker tag payments-flink:1.0 $ACR_LOGIN_SERVER/flink-jobmanager:1.0
docker tag payments-flink:1.0 $ACR_LOGIN_SERVER/flink-taskmanager:1.0

# Push to ACR
docker push $ACR_LOGIN_SERVER/producer:1.0
docker push $ACR_LOGIN_SERVER/consumer:1.0
docker push $ACR_LOGIN_SERVER/api:1.0
docker push $ACR_LOGIN_SERVER/dashboard:1.0
docker push $ACR_LOGIN_SERVER/flink-jobmanager:1.0
docker push $ACR_LOGIN_SERVER/flink-taskmanager:1.0

# Verify images in ACR
az acr repository list --name txnregistrydev
```

### 3. Initialize Terraform

```bash
cd terraform

# Download provider plugins
terraform init

# Validate configuration
terraform fmt -recursive
terraform validate

# Preview changes
terraform plan -out=tfplan
```

### 4. Deploy Infrastructure

```bash
# Apply terraform
terraform apply tfplan

# Save outputs for reference
terraform output > deployment-outputs.txt

# Get kubeconfig
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing
```

### 5. Verify Cluster Connectivity

```bash
# Check cluster info
kubectl cluster-info

# Verify nodes are ready
kubectl get nodes
kubectl describe nodes

# Check namespaces
kubectl get namespaces

# Check pods in txn-analytics namespace
kubectl get pods -n txn-analytics
```

## Testing & Validation

### Phase 1: Infrastructure Readiness

```bash
# 1. Verify persistent volumes
kubectl get pv
kubectl get pvc -n txn-analytics

# 2. Check Kafka deployment
kubectl get pods -n txn-analytics -l app.kubernetes.io/name=kafka
kubectl logs -n txn-analytics -l app.kubernetes.io/name=kafka

# 3. Check MongoDB deployment
kubectl get pods -n txn-analytics -l app.kubernetes.io/name=mongodb
kubectl logs -n txn-analytics -l app.kubernetes.io/name=mongodb

# 4. Verify network connectivity
kubectl run debug-pod --image=busybox --rm -it -- /bin/sh
nslookup kafka-broker-0.kafka-broker-headless.txn-analytics.svc.cluster.local
nslookup mongo-0.mongo-headless.txn-analytics.svc.cluster.local
```

### Phase 2: Application Deployment

```bash
# 1. Check all deployments
kubectl get deployments -n txn-analytics
kubectl describe deployment producer -n txn-analytics

# 2. Stream logs from producer
kubectl logs -f deployment/producer -n txn-analytics

# 3. Check consumer logs for any errors
kubectl logs -f deployment/consumer -n txn-analytics --tail=50

# 4. Verify API health
kubectl get svc api-service -n txn-analytics
API_IP=$(kubectl get svc api-service -n txn-analytics -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Forward port locally to test
kubectl port-forward -n txn-analytics svc/api-service 8000:8000 &
curl -v http://localhost:8000/health
```

### Phase 3: Data Flow Testing

```bash
# 1. Connect to Kafka and create test data
kubectl exec -it kafka-broker-0 -n txn-analytics -- /bin/bash
kafka-console-producer.sh --broker-list localhost:9092 --topic transactions

# Paste sample JSON:
{"transaction_id": "001", "amount": 100, "merchant_id": "M1", "timestamp": "2024-01-01T00:00:00"}

# 2. Verify messages appear in enriched topic
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic transactions_enriched --from-beginning

# 3. Check MongoDB for ingested data
kubectl exec -it mongodb-0 -n txn-analytics -- mongosh
use txn_analytics
db.transactions.findOne()
```

### Phase 4: Autoscaling Test

```bash
# 1. Start load generator
kubectl run -it --rm load-generator -n txn-analytics --image=busybox /bin/shell

# Inside the pod, generate load:
while true; do 
  wget -q -O- http://api-service:8000/health
  sleep 0.1
done

# 2. Monitor HPA in another terminal
kubectl get hpa -n txn-analytics -w

# Watch pods scale up
kubectl get pods -n txn-analytics -l app=api -w

# 3. Stop load generator (Ctrl+C) and watch scale down after ~5 minutes
```

### Phase 5: Monitoring & Logs

```bash
# 1. Get all pod events
kubectl get events -n txn-analytics --sort-by='.lastTimestamp'

# 2. Check resource usage
kubectl top nodes
kubectl top pods -n txn-analytics

# 3. Create port-forwards for dashboard
kubectl port-forward -n txn-analytics svc/dashboard-service 8501:8501 &

# Access dashboard at http://localhost:8501
```

## Production Recommendations

### Security
```bash
# 1. Enable RBAC
kubectl create serviceaccount txn-app -n txn-analytics
kubectl create role txn-role -n txn-analytics --verb=get,list,watch --resource=pods,services
kubectl create rolebinding txn-rolebinding -n txn-analytics --role=txn-role --serviceaccount=txn-analytics:txn-app

# 2. Add network policies
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-ingress
  namespace: txn-analytics
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

# 3. Enable pod security policies
kubectl label namespace txn-analytics pod-security.kubernetes.io/enforce=baseline
```

### Monitoring
```bash
# Install Prometheus for metrics collection
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Install loki for log aggregation
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack -n logging --create-namespace
```

### Backup & Recovery
```bash
# Backup Kafka state
kubectl exec -it kafka-broker-0 -n txn-analytics -- tar czf - -C /bitnami/kafka/data . > kafka-backup.tar.gz

# Backup MongoDB
kubectl exec -it mongodb-0 -n txn-analytics -- mongodump --archive > mongodb-backup.archive
```

## Troubleshooting

### Pod not starting
```bash
kubectl describe pod <pod-name> -n txn-analytics
kubectl logs <pod-name> -n txn-analytics
```

### Image pull errors
```bash
# Verify ACR credentials
kubectl get secret -n txn-analytics
az acr repository list --name txnregistrydev
```

### Network connectivity issues
```bash
# Test DNS resolution
kubectl run debug --image=alpine --rm -it -- nslookup kafka-broker-0.kafka-broker-headless.txn-analytics.svc.cluster.local

# Test connectivity
kubectl run debug --image=busybox --rm -it -- nc -zv kafka-broker-0.kafka-broker-headless.txn-analytics.svc.cluster.local 9092
```

## Cleanup

To remove all resources:

```bash
# Delete Terraform infrastructure (will take 10-15 minutes)
cd terraform
terraform destroy

# Confirm deletion
az group delete --name payments-streaming-rg --yes
```

## Cost Estimation

- **AKS Cluster**: ~$0.10/hour (monitoring + cluster fee)
- **3 Nodes (D2s_v3)**: ~$0.30/hour each = ~$0.90/hour
- **Premium Storage**: ~$0.05/hour per disk
- **Total Monthly Estimate**: ~$500-800 (dev), higher for production

Use `--min-node-count` and `--max-node-count` to control costs.