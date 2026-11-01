locals {
  # App ID publico e fixo do servidor AAD do AKS; igual em todos os tenants.
  aks_aad_server_id = "6dae42f8-4368-4678-94ff-3960e28e3630"

  addon_namespaces = toset(["traefik", "cert-manager", "reloader"])
}

data "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

# Namespaces dos add-ons: declarados aqui em vez de create_namespace no
# helm_release, para o Terraform ser dono do ciclo de vida de todos eles.
resource "kubernetes_namespace" "addons" {
  for_each = local.addon_namespaces

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/part-of" = each.value
    }
  }
}

resource "kubernetes_namespace" "applications" {
  for_each = var.application_namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/part-of" = each.value
    }
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = kubernetes_namespace.addons["traefik"].metadata[0].name
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version

  values = [file("${path.module}/values/traefik.yaml")]

  atomic  = true
  wait    = true
  timeout = 600
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.addons["cert-manager"].metadata[0].name
  repository = "oci://quay.io/jetstack/charts"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version

  values = [file("${path.module}/values/cert-manager.yaml")]

  atomic  = true
  wait    = true
  timeout = 600
}

# O ClusterIssuer e um CRD do cert-manager. Via kubernetes_manifest o plan
# falharia antes do CRD existir; um chart local nao valida no plan, entao o
# apply inteiro roda numa passada. O e-mail entra como value, nao como
# substituicao de string em runtime.
resource "helm_release" "cluster_issuers" {
  name      = "cluster-issuers"
  namespace = kubernetes_namespace.addons["cert-manager"].metadata[0].name
  chart     = "${path.module}/../../../charts/cluster-issuers"

  set {
    name  = "acme.email"
    value = var.acme_email
  }

  set {
    name  = "ingressClassName"
    value = "traefik"
  }

  atomic  = true
  wait    = true
  timeout = 300

  depends_on = [helm_release.cert_manager, helm_release.traefik]
}

# Substitui o `kubectl get svc -n traefik` do processo antigo: o IP para o
# registro DNS sai como output do apply.
data "kubernetes_service" "traefik" {
  metadata {
    name      = helm_release.traefik.name
    namespace = kubernetes_namespace.addons["traefik"].metadata[0].name
  }

  depends_on = [helm_release.traefik]
}

# ---------------------------------------------------------------------------
# External Secrets Operator: le o Key Vault via workload identity e materializa
# os Secrets. Substitui o sync-k8s-secret.py, que montava o Secret em runtime
# dentro do CI e o aplicava com kubectl.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "apps" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
}

data "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${var.cluster_name}-external-secrets"
  resource_group_name = var.resource_group_name
}

locals {
  external_secrets_namespace = "external-secrets"
}

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = local.external_secrets_namespace
    labels = {
      "app.kubernetes.io/part-of" = local.external_secrets_namespace
    }
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_chart_version

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name = "external-secrets"
      annotations = {
        "azure.workload.identity/client-id" = data.azurerm_user_assigned_identity.external_secrets.client_id
      }
    }
    podLabels      = { "azure.workload.identity/use" = "true" }
    resources      = var.external_secrets_resources
    webhook        = { resources = var.external_secrets_resources }
    certController = { resources = var.external_secrets_resources }
  })]

  atomic  = true
  wait    = true
  timeout = 600
}

# Fecha a lacuna do envFrom: variavel de ambiente e lida no start do
# container, entao trocar o Secret nao afeta pod em execucao. O Reloader
# observa Secrets e ConfigMaps e faz patch na anotacao do pod template do
# Deployment que os consome, o que dispara um rolling update.
resource "helm_release" "reloader" {
  name       = "reloader"
  namespace  = kubernetes_namespace.addons["reloader"].metadata[0].name
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = var.reloader_chart_version

  values = [yamlencode({
    reloader = {
      watchGlobally = true
      deployment    = { resources = var.reloader_resources }
    }
  })]

  atomic  = true
  wait    = true
  timeout = 600
}

# ClusterSecretStore e um ExternalSecret por release. Fora do chart da
# aplicacao de proposito: o Job de migracao roda em pre-upgrade e precisa do
# Secret ja existindo, o que nao aconteceria se ele nascesse no mesmo release.
resource "helm_release" "app_secrets" {
  name      = "app-secrets"
  namespace = kubernetes_namespace.external_secrets.metadata[0].name
  chart     = "${path.module}/../../../charts/app-secrets"

  values = [yamlencode({
    refreshInterval = var.secret_refresh_interval
    keyVault = {
      url      = data.azurerm_key_vault.apps.vault_uri
      tenantId = data.azurerm_client_config.current.tenant_id
    }
    serviceAccount = {
      name      = "external-secrets"
      namespace = local.external_secrets_namespace
    }
    releases = var.app_secrets
  })]

  atomic  = true
  wait    = true
  timeout = 300

  depends_on = [helm_release.external_secrets, kubernetes_namespace.applications]
}
