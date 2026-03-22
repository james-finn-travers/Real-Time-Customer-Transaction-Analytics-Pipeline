variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "payments-streaming-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.27"
}

variable "node_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 3
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "min_node_count" {
  description = "Minimum number of nodes (for autoscaling)"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of nodes (for autoscaling)"
  type        = number
  default     = 10
}