variable "subscription_id" {
  description = "Azure subscription that will own the AKS resources."
  type        = string
}

# Uma regiao e um resource group para tudo: cluster, rede, ACR e identidades.
# Mudar estes valores forca recriacao dos recursos; nao sao editaveis in-place.
variable "location" {
  description = "Azure region for every resource in this stack."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Single resource group for the cluster, network, ACR and identities."
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

variable "github_infra_repository" {
  description = "GitHub owner/repository of this infra repo, allowed to apply Kubernetes config via OIDC."
  type        = string
  default     = "clemeson/byteflip-infra"
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

variable "key_vault_name" {
  description = "Globally unique Key Vault name: 3-24 alphanumeric characters or dashes."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "key_vault_name must be 3-24 chars, start with a letter, and contain only letters, numbers and dashes."
  }
}

# Precisam casar com o que terraform/cluster/prod instala: o subject do
# federated credential e literalmente namespace + service account.
variable "external_secrets_namespace" {
  description = "Namespace where the External Secrets Operator runs."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "ServiceAccount name of the External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

# Repos de aplicacao, alem do simplaca, autorizados a publicar imagem e
# implantar via OIDC. A chave e so o nome usado no federated credential; o
# valor e o owner/repo, que vai literalmente para o subject do token.
#
# O simplaca ficou nos recursos nomeados (github_build/github_deploy) porque
# dobra-los para ca exigiria `terraform state mv`. Vale fazer num momento
# calmo, nao junto de um apply que cria node pool.
variable "github_app_repositories" {
  description = "Extra GitHub owner/repository entries allowed to build and deploy via OIDC."
  type        = map(string)
  default = {
    zisp-api       = "clemeson/zisp-api"
    zisp-vpn-api   = "clemeson/zisp-vpn-api"
    zisp-super-api = "clemeson/zisp-super-api"
  }
}

# Desligado por default: a quota regional de vCPU esta esgotada pelos dois nos
# do pool system. Ligue depois que o aumento for aprovado.
variable "zisp_node_pool_enabled" {
  description = "Create the dedicated ZISP node pool. Requires regional vCPU quota headroom."
  type        = bool
  default     = false
}

variable "zisp_node_vm_size" {
  description = "SKU of the dedicated ZISP node pool. Must fit Postgres, two Redis and three APIs."
  type        = string
  default     = "Standard_D2as_v7"
}
