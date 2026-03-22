# Terraform Configuration for Payments Streaming Platform

This directory contains **Kubernetes-based Terraform configurations** to deploy the payments-streaming-platform to Azure using AKS (Azure Kubernetes Service) for enterprise-grade container orchestration.

## Architecture

- **AKS Cluster**: Managed Kubernetes service with auto-scaling nodes
- **Kafka & MongoDB**: Stateful services deployed via Helm charts
- **Flink**: Stream processing with JobManager and TaskManager pods
- **Application Services**: Producer, Consumer, API, and Dashboard as Kubernetes deployments
- **Auto-scaling**: Horizontal Pod Autoscalers (HPA) for API and Consumer
- **Persistent Storage**: Premium SSD storage for stateful workloads
- **Azure Container Registry**: Private container image repository
- **Load Balancers**: External access to API, Dashboard, and Flink UI

## Prerequisites

1. **Install Terraform**: https://www.terraform.io/downloads
2. **Install Azure CLI**: `az login` and authenticate
3. **Install kubectl**: https://kubernetes.io/docs/tasks/tools/tools/
4. **Install Helm**: https://helm.sh/docs/intro/install/
5. **Install Docker**: For building container images
6. **Azure subscription** with appropriate quotas

## Quick Start

### 1. Build Container Images

```bash
cd /home/james/payments-streaming-platform

# Build all docker images
docker build -f infra/Dockerfile.producer -t payments-producer:1.0 .
docker build -f infra/Dockerfile.consumer -t payments-consumer:1.0 .
docker build -f infra/Dockerfile.api -t payments-api:1.0 .
docker build -f infra/Dockerfile.dashboard -t payments-dashboard:1.0 .
docker build -f infra/Dockerfile.flink -t payments-flink:1.0 .
```

### 2. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

### 3. Configure kubectl

```bash
# Get kubeconfig
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing
```

### 4. Verify Deployment

```bash
# Check namespace and pods
kubectl get pods -n txn-analytics

# Check services
kubectl get svc -n txn-analytics

# View logs
kubectl logs -f deployment/producer -n txn-analytics
```

## Architecture Details

### Kubernetes Resources

- **Namespace**: `txn-analytics` for isolation
- **Deployments**: 6 application deployments with rolling updates
- **Services**: 3 LoadBalancer services for external access
- **ConfigMap**: Application configuration
- **Secrets**: Database credentials
- **PVCs**: 3 persistent volumes for Kafka, Zookeeper, MongoDB
- **HPAs**: Auto-scaling for API (2-10 replicas) and Consumer (1-5 replicas)

### High Availability

- **Pod Replicas**: Multiple instances for resilience
- **Health Checks**: Liveness and readiness probes
- **Resource Limits**: CPU and memory constraints
- **Persistent Storage**: Data persistence across pod restarts
- **Load Balancing**: Traffic distribution across pods

### Security

- **Network Policies**: Ready for implementation
- **RBAC**: Role-based access control prepared
- **Secrets Management**: Sensitive data in Kubernetes secrets
- **Container Registry**: Private ACR with AKS integration

## Cost Optimization

### Deploy-on-Demand (Recommended for Portfolio)

```bash
# Deploy for demo (25 minutes)
terraform apply

# Demo for 2-4 hours (~$5-10 cost)

# Cleanup
terraform destroy
```

**Monthly Cost**: $15-20 (vs $390 always-on)

### Always-On Demo

- Single node AKS cluster
- Spot instances for cost savings
- Reserved instances for longer periods

**Monthly Cost**: $50-60

## Testing

### Infrastructure Testing

```bash
# Check all pods running
kubectl get pods -n txn-analytics

# Verify services have external IPs
kubectl get svc -n txn-analytics

# Test API health
curl http://<api-external-ip>:8000/health
```

### Application Testing

```bash
# Send test transaction
kubectl exec -it deployment/producer -n txn-analytics -- python -c "
import requests
requests.post('http://kafka-broker-0.kafka-broker-headless:9092', 
              data='test transaction')
"

# Check consumer logs
kubectl logs -f deployment/consumer -n txn-analytics

# Verify data in MongoDB
kubectl exec -it mongodb-0 -n txn-analytics -- mongosh txn_analytics --eval "db.transactions.count()"
```

### Autoscaling Testing

```bash
# Generate load on API
kubectl run load-generator --image=busybox -n txn-analytics --rm -it -- /bin/sh
# Inside pod: while true; do wget -q http://api-service:8000/health; done

# Monitor scaling
kubectl get hpa -n txn-analytics -w
kubectl get pods -n txn-analytics -l app=api -w
```

## Troubleshooting

### Common Issues

**Pods not starting:**
```bash
kubectl describe pod <pod-name> -n txn-analytics
kubectl logs <pod-name> -n txn-analytics
```

**Image pull errors:**
```bash
# Verify ACR login
az acr login --name txnregistrydev

# Check image exists
az acr repository list --name txnregistrydev
```

**Service connectivity:**
```bash
# Test DNS resolution
kubectl run debug --image=alpine -n txn-analytics --rm -it -- nslookup kafka-broker-0

# Check network policies
kubectl get networkpolicies -n txn-analytics
```

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Confirm deletion
az group delete --name payments-streaming-rg --yes
```

## Files Overview

| File | Purpose | Lines |
|------|---------|-------|
| `main.tf` | AKS cluster + K8s deployments | 770 |
| `variables.tf` | Input variables | 46 |
| `outputs.tf` | Exported values | 64 |
| `providers.tf` | Provider configurations | 11 |
| `helm-values/kafka-values.yaml` | Kafka Helm config | 40 |
| `helm-values/mongodb-values.yaml` | MongoDB Helm config | 36 |
| `validate.py` | HCL syntax validator | 170 |
| `analyze.py` | Configuration analyzer | 250 |

## Enterprise Features

✅ **Multi-cloud ready** - Portable to AWS EKS, GCP GKE  
✅ **Compliance ready** - Network policies, RBAC, audit logs  
✅ **Production-grade** - Health checks, resource limits, monitoring  
✅ **Cost-conscious** - Deploy-on-demand, auto-scaling  
✅ **Highly available** - Replicas, persistent storage, load balancing  
✅ **Secure** - Secrets management, private registry, VNet isolation  

## For Big 5 Canadian Banks

This configuration demonstrates:
- Enterprise Kubernetes architecture
- Production deployment practices
- Cost optimization thinking
- Regulatory compliance readiness
- Multi-cloud portability

Perfect for impressing financial institutions that value infrastructure expertise and responsible resource management.

## Prerequisites

1. **Install Terraform**: https://www.terraform.io/downloads
2. **Install Azure CLI**: `az login` and authenticate
3. **Install kubectl**: https://kubernetes.io/docs/tasks/tools/
4. **Install Helm**: https://helm.sh/docs/intro/install/
5. **Install Docker**: For building container images
6. **Azure subscription** with sufficient quota

## Deployment - Kubernetes (Recommended)

### Step 1: Build Container Images

```bash
# Build each service image and push to ACR
# Update the image tags in main.tf after creation

docker build -f infra/Dockerfile.producer -t producer:latest .
docker build -f infra/Dockerfile.consumer -t consumer:latest .
docker build -f infra/Dockerfile.api -t api:latest .
docker build -f infra/Dockerfile.dashboard -t dashboard:latest .
docker build -f infra/Dockerfile.flink -t flink-jobmanager:latest -t flink-taskmanager:latest .
```

### Step 2: Initialize and Deploy

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

### Step 3: Configure kubectl

```bash
# Download kubeconfig (output from terraform)
az aks get-credentials --resource-group payments-streaming-rg --name txn-aks-dev --overwrite-existing

# Verify cluster connection
kubectl cluster-info
kubectl get nodes
```

## Testing - Kubernetes Deployment

### 1. Check Pod Status

```bash
# Switch to txn-analytics namespace
kubectl config set-context --current --namespace=txn-analytics

# View running pods
kubectl get pods
kubectl describe pod <pod-name>

# View logs
kubectl logs -f deployment/producer
kubectl logs -f deployment/consumer
kubectl logs -f deployment/api
```

### 2. Test Services

```bash
# Get service endpoints
kubectl get svc

# Forward ports for local testing
kubectl port-forward svc/api-service 8000:8000
kubectl port-forward svc/dashboard-service 8501:8501
kubectl port-forward svc/flink-jobmanager 8081:8081

# In another terminal, test the API
curl http://localhost:8000/health

# Access Flink Web UI at http://localhost:8081
# Access Dashboard at http://localhost:8501
```

### 3. Monitor Autoscaling

```bash
# Watch HPA status
kubectl get hpa -w

# Simulate load on API to trigger autoscaling
kubectl run -it --rm load-generator --image=busybox /bin/sh
# Inside pod:
while true; do wget -q -O- http://api-service:8000/health; done
```

### 4. Check Kafka Topics

```bash
# Connect to Kafka broker pod
kubectl exec -it kafka-broker-0 -- /bin/bash

# List topics
kafka-topics.sh --list --bootstrap-server localhost:9092

# Consume from topic
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic transactions --from-beginning
```

### 5. Verify MongoDB

```bash
# Connect to MongoDB
kubectl exec -it mongodb-0 -- mongosh

# In MongoDB shell
show databases
use txn_analytics
show collections
```

## Deployment - Cloud-Native Services

```bash
# Use main.tf instead
terraform init

# Plan and apply (see notes below)
terraform plan -out=tfplan
terraform apply tfplan
```

## Cleanup

To destroy all resources:

```bash
# Destroy Kubernetes resources
terraform destroy -target=helm_release.kafka
terraform destroy -target=helm_release.mongodb

# Destroy all infrastructure
terraform destroy
```

## Enterprise Features (Kubernetes)

✅ **Multi-cloud ready**: Run on AKS, EKS, or on-premises
✅ **Auto-scaling**: Automatically scales pods based on metrics
✅ **Resource isolation**: Namespace-based separation
✅ **High availability**: Replica sets, health checks, readiness probes
✅ **Container registry**: Private ACR for secure image storage
✅ **Monitoring ready**: Metrics exposed for Prometheus/Azure Monitor
✅ **Compliance**: Fine-grained RBAC, network policies available

## Architecture Comparison

| Feature | Cloud-Native | Kubernetes |
|---------|-------------|-----------|
| **Multi-cloud** | ❌ Azure only | ✅ Any cloud |
| **Familiar to DevOps** | ❌ | ✅ Industry standard |
| **Regulatory control** | ⚠️ Limited | ✅ Full control |
| **Learning curve** | ✅ Easy | ⚠️ Moderate |
| **Cost optimization** | ✅ Good | ✅ Excellent |
| **Enterprise adoption** | ⚠️ Growing | ✅ Proven |

## Notes

- Kubernetes deployment is **better for enterprise** (banks, large orgs)
- Cloud-native is simpler but locks you into Azure
- Container images must be built and pushed to ACR before deployment
- Ensure VNet has proper security groups configured
- Enable monitoring/logging for production use
- Costs vary; AKS cheaper with reserved instances