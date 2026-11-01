variable "subscription_id" {
  description = "Azure subscription that owns the AKS cluster."
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster to configure. Must already exist (terraform/aks/prod)."
  type        = string
  default     = "personal-prod"
}

variable "resource_group_name" {
  description = "Resource group of the AKS cluster."
  type        = string
  default     = "personal-aks-eastus2-prod"
}

variable "acme_email" {
  description = "Let's Encrypt contact address for the ClusterIssuer."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.acme_email))
    error_message = "acme_email must be a single valid email address."
  }
}

variable "traefik_chart_version" {
  description = "Pinned Traefik chart version."
  type        = string
  default     = "41.4.0"
}

variable "cert_manager_chart_version" {
  description = "Pinned cert-manager chart version."
  type        = string
  default     = "v1.21.2"
}

# Namespaces das aplicacoes. O chart da app nao cria namespace, e a identidade
# de deploy do CI tem RBAC Writer escopado no namespace: ela nao pode criar.
variable "application_namespaces" {
  description = "Namespaces owned by this stack, mapped to their part-of label."
  type        = map(string)
  default = {
    simplaca = "simplaca"
    postlet  = "postlet"
  }
}

variable "key_vault_name" {
  description = "Key Vault created by terraform/aks/prod (output key_vault_name)."
  type        = string
}

variable "external_secrets_chart_version" {
  description = "Pinned External Secrets Operator chart version."
  type        = string
  default     = "0.21.0"
}

# O chart do ESO nao define requests. Sem isso os pods ficam BestEffort e sao
# os primeiros despejados sob pressao de memoria -- justamente o controller
# que entrega segredo para todo mundo.
variable "external_secrets_resources" {
  description = "Resource requests and limits applied to the operator pods."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "25m", memory = "96Mi" }
    limits   = { cpu = "200m", memory = "256Mi" }
  }
}

# Um segredo no Key Vault por release, com um objeto JSON dentro; cada chave
# do JSON vira uma chave do Secret do Kubernetes.
variable "app_secrets" {
  description = "Releases that receive a Secret from Key Vault via External Secrets."
  type = list(object({
    name           = string
    namespace      = string
    secretName     = string
    keyVaultSecret = string
  }))
  default = [{
    name           = "simplaca-api"
    namespace      = "simplaca"
    secretName     = "simplaca-api-env"
    keyVaultSecret = "simplaca-api-env"
  }]
}
