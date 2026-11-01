variable "subscription_id" {
  description = "Azure subscription that will own the AKS resources."
  type        = string
}

variable "location" {
  description = "Azure region of the existing ACR and GitHub identities."
  type        = string
  default     = "brazilsouth"
}

variable "resource_group_name" {
  type    = string
  default = "personal-aks-prod"
}

variable "aks_location" {
  description = "Azure region for the AKS cluster and its network."
  type        = string
  default     = "eastus2"
}

variable "aks_resource_group_name" {
  description = "Resource group for the AKS cluster and its network."
  type        = string
  default     = "personal-aks-eastus2-prod"
}

variable "cluster_name" {
  type    = string
  default = "personal-prod"
}

variable "acr_name" {
  description = "Globally unique ACR name: 5-50 alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must contain 5-50 letters or numbers."
  }
}

variable "github_simplaca_repository" {
  description = "GitHub owner/repository allowed to build and deploy Simplaca via OIDC."
  type        = string
  default     = "clemeson/simplaca-backend"
}

variable "aks_admin_principal_id" {
  description = "Microsoft Entra object ID of the human operator or admin group."
  type        = string
}

variable "system_node_vm_size" {
  description = "AKS system pool SKU. Confirm regional capacity and quota before apply."
  type        = string
  default     = "Standard_D2as_v7"
}

variable "system_node_min_count" {
  type = number

  # Production system pools need at least two nodes.
  default = 2

  validation {
    condition     = var.system_node_min_count >= 2
    error_message = "A production system node pool requires at least two nodes."
  }
}
