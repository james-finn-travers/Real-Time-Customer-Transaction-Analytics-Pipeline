output "aks_cluster_id" {
  value       = azurerm_kubernetes_cluster.aks.id
  description = "AKS cluster ID"
}

output "aks_cluster_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "AKS cluster name"
}

output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "Azure resource group name"
}

output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "Azure Container Registry login server"
}

output "acr_admin_username" {
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
  description = "ACR admin username"
}

output "kubernetes_cluster_host" {
  value       = azurerm_kubernetes_cluster.aks.kube_config.0.host
  description = "Kubernetes cluster host"
  sensitive   = true
}

output "flink_jobmanager_url" {
  value       = try(
    "http://${kubernetes_service.flink_jobmanager.status.0.load_balancer.0.ingress.0.ip}:8081",
    "pending - check kubectl service"
  )
  description = "Flink JobManager Web UI URL"
}

output "api_endpoint" {
  value       = try(
    "http://${kubernetes_service.api.status.0.load_balancer.0.ingress.0.ip}:8000",
    "pending - check kubectl service"
  )
  description = "API endpoint"
}

output "dashboard_endpoint" {
  value       = try(
    "http://${kubernetes_service.dashboard.status.0.load_balancer.0.ingress.0.ip}:8501",
    "pending - check kubectl service"
  )
  description = "Dashboard endpoint"
}

output "namespace" {
  value       = kubernetes_namespace.txn.metadata[0].name
  description = "Kubernetes namespace for the application"
}

output "kubeconfig_command" {
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
  description = "Command to download kubeconfig"
}