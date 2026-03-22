# Kubernetes-based deployment for Payments Streaming Platform
# Uses AKS (Azure Kubernetes Service) for enterprise-grade container orchestration

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~>2.11"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "txn-vnet-${var.environment}"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.0.0/16"]
}

# Create AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "txn-aks-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "txn-aks-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                 = "default"
    node_count           = var.node_count
    vm_size              = var.node_vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    enable_auto_scaling  = true
    min_count            = var.min_node_count
    max_count            = var.max_node_count
    orchestrator_version = var.kubernetes_version
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  depends_on = [azurerm_subnet.aks]
}

# Configure Kubernetes Provider
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# Create namespace
resource "kubernetes_namespace" "txn" {
  metadata {
    name = "txn-analytics"
    labels = {
      environment = var.environment
    }
  }
}

# Storage Class for persistent volumes
resource "kubernetes_storage_class" "fast" {
  metadata {
    name = "fast-ssd"
  }
  storage_provisioner = "kubernetes.io/azure-disk"
  parameters = {
    skuName = "Premium_LRS"
  }
  reclaim_policy = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}

# Create persistent volume claims for stateful services
resource "kubernetes_persistent_volume_claim" "kafka_pvc" {
  metadata {
    name      = "kafka-data"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.fast.metadata[0].name
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "zookeeper_pvc" {
  metadata {
    name      = "zookeeper-data"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.fast.metadata[0].name
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mongo_pvc" {
  metadata {
    name      = "mongo-data"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.fast.metadata[0].name
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

# ConfigMap for application configuration
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "txn-config"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }
  data = {
    KAFKA_BOOTSTRAP_SERVERS = "kafka-broker-0.kafka-broker-headless.txn-analytics.svc.cluster.local:9092"
    KAFKA_TOPIC             = "transactions"
    KAFKA_ENRICHED_TOPIC    = "transactions_enriched"
    KAFKA_ANOMALY_TOPIC     = "anomalies"
    KAFKA_DAILY_SPEND_TOPIC = "daily_spend"
    MONGO_DB                = "txn_analytics"
    ANOMALY_SD_THRESHOLD    = "3.0"
    FLINK_PARALLELISM       = "2"
    LOG_LEVEL               = "INFO"
  }
}

# Secret for sensitive data
resource "kubernetes_secret" "mongodb_secret" {
  metadata {
    name      = "mongodb-credentials"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }
  type = "Opaque"
  data = {
    MONGO_URI = base64encode("mongodb://mongo-0.mongo-headless.txn-analytics.svc.cluster.local:27017")
  }
}

# Azure Container Registry for private images
resource "azurerm_container_registry" "acr" {
  name                = "txnregistry${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Attach ACR to AKS
resource "azurerm_role_assignment" "aks_acr" {
  scope              = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Helm release for Kafka
resource "helm_release" "kafka" {
  name       = "kafka"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "kafka"
  namespace  = kubernetes_namespace.txn.metadata[0].name
  version    = "28.0.0"

  values = [
    templatefile("${path.module}/helm-values/kafka-values.yaml", {
      storage_class = kubernetes_storage_class.fast.metadata[0].name
      namespace     = kubernetes_namespace.txn.metadata[0].name
    })
  ]

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Helm release for MongoDB
resource "helm_release" "mongodb" {
  name       = "mongodb"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "mongodb"
  namespace  = kubernetes_namespace.txn.metadata[0].name
  version    = "14.0.0"

  values = [
    templatefile("${path.module}/helm-values/mongodb-values.yaml", {
      storage_class = kubernetes_storage_class.fast.metadata[0].name
      namespace     = kubernetes_namespace.txn.metadata[0].name
    })
  ]

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Flink JobManager Deployment
resource "kubernetes_deployment" "flink_jobmanager" {
  metadata {
    name      = "flink-jobmanager"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "flink-jobmanager"
      }
    }

    template {
      metadata {
        labels = {
          app = "flink-jobmanager"
        }
      }

      spec {
        container {
          image = "${azurerm_container_registry.acr.login_server}/flink-jobmanager:latest"
          name  = "jobmanager"

          ports {
            container_port = 8081
            name           = "web-ui"
          }

          ports {
            container_port = 6123
            name           = "rpc"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [helm_release.kafka]
}

# Flink TaskManager Deployment
resource "kubernetes_deployment" "flink_taskmanager" {
  metadata {
    name      = "flink-taskmanager"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "flink-taskmanager"
      }
    }

    template {
      metadata {
        labels = {
          app = "flink-taskmanager"
        }
      }

      spec {
        container {
          image = "${azurerm_container_registry.acr.login_server}/flink-taskmanager:latest"
          name  = "taskmanager"

          env {
            name  = "JOB_MANAGER_RPC_ADDRESS"
            value = "flink-jobmanager.${kubernetes_namespace.txn.metadata[0].name}.svc.cluster.local"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [kubernetes_deployment.flink_jobmanager]
}

# Producer Deployment
resource "kubernetes_deployment" "producer" {
  metadata {
    name      = "producer"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "producer"
      }
    }

    template {
      metadata {
        labels = {
          app = "producer"
        }
      }

      spec {
        container {
          image = "${azurerm_container_registry.acr.login_server}/producer:latest"
          name  = "producer"

          env {
            name  = "TARGET_TPS"
            value = "1000"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [helm_release.kafka]
}

# Consumer Deployment
resource "kubernetes_deployment" "consumer" {
  metadata {
    name      = "consumer"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "consumer"
      }
    }

    template {
      metadata {
        labels = {
          app = "consumer"
        }
      }

      spec {
        container {
          image = "${azurerm_container_registry.acr.login_server}/consumer:latest"
          name  = "consumer"

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.mongodb_secret.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [helm_release.kafka, helm_release.mongodb]
}

# API Deployment
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app = "api"
      }
    }

    template {
      metadata {
        labels = {
          app = "api"
        }
      }

      spec {
        container {
          image = "${azurerm_container_registry.acr.login_server}/api:latest"
          name  = "api"

          ports {
            container_port = 8000
            name           = "http"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.mongodb_secret.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path   = "/ready"
              port   = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [helm_release.mongodb]
}

# Dashboard Deployment
resource "kubernetes_deployment" "dashboard" {
  metadata {
    name      = "dashboard"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "dashboard"
        }
      }

      spec {
        container {
          image = "${azurerm_container_registry.acr.login_server}/dashboard:latest"
          name  = "dashboard"

          ports {
            container_port = 8501
            name           = "http"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.mongodb_secret.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [helm_release.mongodb]
}

# Service for Flink JobManager
resource "kubernetes_service" "flink_jobmanager" {
  metadata {
    name      = "flink-jobmanager"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    selector = {
      app = "flink-jobmanager"
    }

    port {
      port        = 8081
      target_port = 8081
      name        = "web"
    }

    port {
      port        = 6123
      target_port = 6123
      name        = "rpc"
    }

    type = "LoadBalancer"
  }
}

# Service for API
resource "kubernetes_service" "api" {
  metadata {
    name      = "api-service"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    selector = {
      app = "api"
    }

    port {
      port        = 8000
      target_port = 8000
      name        = "http"
    }

    type = "LoadBalancer"
  }
}

# Service for Dashboard
resource "kubernetes_service" "dashboard" {
  metadata {
    name      = "dashboard-service"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    selector = {
      app = "dashboard"
    }

    port {
      port        = 8501
      target_port = 8501
      name        = "http"
    }

    type = "LoadBalancer"
  }
}

# Horizontal Pod Autoscaler for API
resource "kubernetes_horizontal_pod_autoscaler_v2" "api_hpa" {
  metadata {
    name      = "api-hpa"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.api.metadata[0].name
    }

    min_replicas = 2
    max_replicas = 10

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

# Horizontal Pod Autoscaler for Consumer
resource "kubernetes_horizontal_pod_autoscaler_v2" "consumer_hpa" {
  metadata {
    name      = "consumer-hpa"
    namespace = kubernetes_namespace.txn.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.consumer.metadata[0].name
    }

    min_replicas = 1
    max_replicas = 5

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 75
        }
      }
    }
  }
}