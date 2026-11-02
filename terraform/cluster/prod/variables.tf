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
    zisp     = "zisp"
  }
}

variable "key_vault_name" {
  description = "Key Vault created by terraform/aks/prod (output key_vault_name)."
  type        = string
}

variable "external_secrets_chart_version" {
  description = "Pinned External Secrets Operator chart version."
  type        = string
  default     = "2.14.0"
}

variable "reloader_chart_version" {
  description = "Pinned Stakater Reloader chart version."
  type        = string
  default     = "2.2.19"
}

# O Secret vem do operator, nao do release Helm, entao o chart nao consegue
# calcular um checksum dele como faz com o ConfigMap. O Reloader observa o
# Secret e reinicia os Deployments que o consomem quando o valor muda.
variable "reloader_resources" {
  description = "Resource requests and limits for the Reloader controller."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "10m", memory = "48Mi" }
    limits   = { cpu = "100m", memory = "128Mi" }
  }
}

# Intervalo com que o operator relê o Key Vault. O vault nao notifica o
# cluster, entao esta e a latencia de uma troca de valor chegar em producao.
variable "secret_refresh_interval" {
  description = "How often External Secrets re-reads Key Vault."
  type        = string
  default     = "5m"
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

# A lista de releases que recebem Secret saia daqui e passou a vir de
# apps/releases.yaml (local.app_secrets em main.tf), que e o mesmo arquivo que
# alimenta o matrix do workflow de deploy. Mantinha-se a mesma lista em dois
# lugares e nada garantia que batessem.
