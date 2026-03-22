# Kubernetes Deployment: Quick Reference

This directory contains **Kubernetes-only Terraform configurations** for deploying the payments-streaming-platform to Azure AKS. The cloud-native files have been removed to focus on enterprise-grade container orchestration.

## Architecture Overview

**Deployment Strategy: KUBERNETES (AKS)** ⭐ RECOMMENDED FOR BIG 5 BANKS
- **AKS (Azure Kubernetes Service)**: Container orchestration
- **Kafka (Helm)**: Message streaming with 3 replicas
- **MongoDB (Helm)**: Data persistence with replica set
- **Flink**: Stream processing (JobManager + TaskManager pods)
- **Application Services**: Producer, Consumer, API, Dashboard as deployments
- **Auto-scaling**: HPA for API (2-10 replicas) and Consumer (1-5 replicas)
- **Azure Container Registry**: Private image repository
- **Load Balancers**: External access to services

## Key Benefits for Big 5 Banks

✅ **Multi-cloud ready** - Can run on AWS, GCP, Azure, or on-premises  
✅ **Enterprise standard** - Kubernetes is industry standard for banks  
✅ **Compliance control** - Full infrastructure control for regulations  
✅ **Cost optimization** - Deploy-on-demand shows responsibility  
✅ **Production-grade** - Health checks, resource limits, monitoring  
✅ **Security** - Network policies, RBAC, secrets management  

## Files Structure

```
terraform/
├── main.tf                     (770 lines) - AKS + K8s resources
├── variables.tf                (46 lines)  - Input variables
├── outputs.tf                  (64 lines)  - Exported values
├── providers.tf                (11 lines)  - Provider configs
├── helm-values/
│   ├── kafka-values.yaml       (40 lines)  - Kafka Helm config
│   └── mongodb-values.yaml     (36 lines)  - MongoDB Helm config
├── validate.py                 (170 lines) - HCL validator
├── analyze.py                  (250 lines) - Resource analyzer
├── README.md                   - Main deployment guide
├── DEPLOYMENT_GUIDE.md         - Detailed step-by-step
├── QUICK_REFERENCE.md          - This file
└── TEST_RESULTS.md             - Validation report
```

## Quick Deployment

```bash
# 1. Build images
cd /home/james/payments-streaming-platform
docker build -f infra/Dockerfile.producer -t producer:1.0 .
docker build -f infra/Dockerfile.consumer -t consumer:1.0 .
docker build -f infra/Dockerfile.api -t api:1.0 .
docker build -f infra/Dockerfile.dashboard -t dashboard:1.0 .
docker build -f infra/Dockerfile.flink -t flink:1.0 .

# 2. Deploy
cd terraform
terraform init
terraform plan
terraform apply

# 3. Configure kubectl
az aks get-credentials --resource-group payments-streaming-rg --name txn-aks-dev --overwrite-existing

# 4. Verify
kubectl get pods -n txn-analytics
```

## Cost Comparison (Monthly)

| Approach | Cost | Notes |
|----------|------|-------|
| **Deploy-on-demand** | $15-20 | Demo sessions only |
| **Always-on (single node)** | $50-60 | For continuous access |
| **Always-on (3 nodes)** | $390-410 | Full production |

## Why Kubernetes Wins for Banks

### Technical Advantages
- **Multi-cloud portability** - Not locked to Azure
- **Fine-grained control** - Essential for compliance
- **Industry standard** - Every major bank uses K8s
- **Regulatory compliance** - Network policies, audit trails
- **Resource isolation** - Namespaces, RBAC, quotas

### Business Advantages
- **Cost transparency** - Predictable node-based pricing
- **Vendor independence** - Can migrate to AWS/GCP easily
- **Talent alignment** - K8s skills are in high demand
- **Future-proofing** - Works with on-prem deployments

## Resources Deployed

### Infrastructure (Azure)
- 1 AKS Cluster (auto-scaling 2-10 nodes)
- 1 Virtual Network with subnets
- 1 Azure Container Registry
- 1 Resource Group

### Kubernetes Objects
- 1 Namespace (`txn-analytics`)
- 6 Deployments (Flink JM/TM, Producer, Consumer, API, Dashboard)
- 3 Services (LoadBalancer type)
- 1 ConfigMap (app configuration)
- 1 Secret (database credentials)
- 3 PVCs (Kafka, Zookeeper, MongoDB data)
- 2 HPAs (auto-scaling for API & Consumer)
- 1 StorageClass (Premium SSD)

### Stateful Services (Helm)
- Kafka: 3 brokers + Zookeeper
- MongoDB: 3 replicas + arbiter

## Validation Status

✅ **All tests passed** (see TEST_RESULTS.md)
- HCL syntax: VALID
- Resource dependencies: VALID
- Variable references: VALID
- Cross-file consistency: VALID
- Enterprise best practices: IMPLEMENTED

## For Portfolio Projects

### Primary Strategy: Deploy-on-Demand
1. **Local Docker Compose** - Always works, free
2. **Demo video** - Pre-recorded walkthrough
3. **Deploy for interviews** - 25 min setup, $5-10 cost

### Interview Talking Points
- "This runs on Kubernetes, the same platform banks use"
- "Designed for multi-cloud deployment"
- "Includes auto-scaling and high availability"
- "Cost-optimized with deploy-on-demand approach"
- "Production-ready with health checks and monitoring"

## Next Steps

1. **Read DEPLOYMENT_GUIDE.md** for detailed instructions
2. **Run validate.py** to verify configuration
3. **Build Docker images** for your application
4. **Deploy with terraform apply**
5. **Test with kubectl** commands

## Enterprise Readiness Checklist

- ✅ Multi-cloud architecture
- ✅ Auto-scaling (HPA)
- ✅ High availability (replicas)
- ✅ Persistent storage
- ✅ Health checks (liveness/readiness)
- ✅ Resource limits
- ✅ Secrets management
- ✅ Network isolation
- ✅ Load balancing
- ✅ Monitoring ready
- ✅ Cost optimization
- ✅ Security best practices

**Perfect for Big 5 Canadian bank interviews!** 🚀
| **Cost predictability** | ✅ Per-service costs | ✅ Node-based, more predictable |
| **Scaling** | ✅ Auto (managed) | ✅ Auto (HPA), more granular |
| **Data residency** | ✅ Easy to control | ✅ Easy to control |

## Deployment Comparison

### Cloud-Native Deployment
```bash
cd terraform
terraform init
terraform plan
terraform apply
# Takes 10-15 minutes
# Automatically configures everything
```

### Kubernetes Deployment
```bash
cd terraform
docker build -t images...
az acr login && docker push...  # Push images to registry
terraform init
terraform plan
terraform apply
kubectl get pods -n txn-analytics  # Verify deployment
# Takes 20-30 minutes (includes image builds/pushes)
# More manual verification required
```

## Cost Comparison (Monthly Estimates - USD)

### Cloud-Native (Minimal workload)
- 1 Event Hubs (Standard): $84
- 1 Cosmos DB: $24 + data storage
- 1 Stream Analytics job: $4
- 1 Function App: $0-10 (consumption)
- 1 App Service (Basic): $10-20
- **Total: ~$120-140/month**

### Kubernetes (3 nodes, dev environment)
- AKS cluster: ~$73/month
- 3 x Standard_D2s_v3 VMs: ~$270/month
- Premium storage (3 disks): ~$30/month
- Load Balancers: ~$16/month
- **Total: ~$390-410/month**

**Note**: Kubernetes costs scale linearly with nodes; Cloud-native costs increase with usage

## For Big 5 Canadian Banks

**RECOMMENDATION: Use Kubernetes (main.tf)**

**Why:**
1. **Compliance & Audit**: Full infrastructure control
2. **Regulatory**: Bank of Canada, OSFI, SOX compliance easier
3. **Security**: Network policies, RBAC at container level
4. **Multi-cloud**: RBC uses AWS+Azure; ability to run anywhere key
5. **Cost control**: Support for Reserved Instances across clouds
6. **Talent**: Enterprise knows Kubernetes (not Event Hubs)
7. **Future-proof**: Can migrate to on-prem or other clouds

**Anti-patterns for banks:**
- ❌ Azure-only (vendor lock-in concerns)
- ❌ Serverless (compliance gaps with Lambda/Functions)
- ❌ Fully managed services (audit trail, control requirements)

## Migration Path

If you start with Cloud-Native and want to move to Kubernetes:

1. Keep both Terraform configurations
2. Deploy Kubernetes in parallel
3. Gradually migrate workloads
4. Decommission cloud-native resources once verified

## Environment Variables for Deployment

### Cloud-Native
```bash
export TF_VAR_resource_group_name="payments-streaming-rg"
export TF_VAR_location="East US"
export TF_VAR_environment="dev"
```

### Kubernetes
```bash
export TF_VAR_resource_group_name="payments-streaming-rg"
export TF_VAR_location="East US"
export TF_VAR_environment="dev"
export TF_VAR_kubernetes_version="1.27"
export TF_VAR_node_count="3"
export TF_VAR_min_node_count="2"
export TF_VAR_max_node_count="10"
```

## Quick Start

### For Learning/Prototyping
```bash
# Use Cloud-Native
terraform init
terraform plan
terraform apply
```

### For Enterprise Portfolio
```bash
# Use Kubernetes
terraform init -backend-config=key=kubernetes.tfstate
terraform plan
terraform apply

# Build and push images
docker build -t my-image:1.0 .
az acr login && docker push my-image:1.0

# Deploy to cluster
kubectl apply -f main.tf
```

## Next Steps

1. **Choose your approach** based on your goals
2. **Install required tools** (Terraform, Azure CLI, kubectl, Docker)
3. **Read the relevant deployment guide**:
   - Cloud-Native: See README.md
   - Kubernetes: See DEPLOYMENT_GUIDE.md
4. **Start with `terraform plan`** to preview changes
5. **Test incrementally** (deploy, verify, test)

## References

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)