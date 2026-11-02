locals {
  tags = {
    ManagedBy   = "terraform"
    Environment = "prod"
    Project     = "cluster_byteflip"
  }
}

data "azurerm_client_config" "current" {}

# Endereco Terraform mantido como "aks" de proposito: ele ja aponta para
# personal-aks-eastus2-prod no state. Renomear o endereco exigiria
# terraform state mv num RG que contem o cluster com prevent_destroy.
resource "azurerm_resource_group" "aks" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  address_space       = ["10.80.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.80.0.0/20"]
}

resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "${var.cluster_name}-control-plane"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "github_build" {
  name                = "${var.cluster_name}-github-build"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github_build" {
  name                      = "github-simplaca-build-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_build.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_simplaca_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "github_build_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github_build.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_user_assigned_identity" "github_deploy" {
  name                = "${var.cluster_name}-github-deploy"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github_deploy" {
  name                      = "github-simplaca-deploy-prod"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_simplaca_repository}:environment:production"
}

# Segunda credencial na MESMA identidade de deploy: o repo da infra aplica
# mudanca de objeto Kubernetes (HPA, resources, probes, ingress) sem imagem
# nova. Precisa das mesmas permissoes, entao nao ha identidade separada.
resource "azurerm_federated_identity_credential" "github_deploy_infra" {
  name                      = "github-infra-config-prod"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_infra_repository}:environment:production"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  dns_prefix          = var.cluster_name
  sku_tier            = "Free"

  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_vm_size
    node_count           = var.system_node_min_count
    auto_scaling_enabled = false
    os_disk_size_gb      = 64
    vnet_subnet_id       = azurerm_subnet.nodes.id

    # Declarado para casar com o default que o AKS aplica. Sem isso o
    # Terraform tenta remover o bloco em todo plan.
    #
    # Atencao: 10% de 2 nos arredonda para 1 no extra durante upgrade, e a
    # quota regional de 4 vCPU ja esta toda consumida pelos dois nos. Um
    # upgrade de node pool vai falhar por quota enquanto ela nao aumentar.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_control_plane.id]
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  local_account_disabled = true

  depends_on = [azurerm_role_assignment.aks_network]

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.81.0.0/16"
    dns_service_ip    = "10.81.0.10"
  }

  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  tags                              = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "github_deploy_cluster_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_user_assigned_identity.github_deploy.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_deploy_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.github_deploy.principal_id
  principal_type       = "ServicePrincipal"
}

# Escopo no cluster, nao num namespace: o CI publica qualquer release deste
# repositorio sem precisar de um role assignment novo por produto.
#
# RBAC Writer cobre Deployment, Service, Ingress, HPA, Secret, ConfigMap, Job,
# PVC, PDB e ServiceAccount em todos os namespaces, e deliberadamente NAO
# cobre namespaces/write, CRDs nem Role/RoleBinding -- entao o CI nao cria
# namespace nem escala o proprio privilegio. Namespaces e add-ons vem do
# terraform/cluster/prod, aplicado com a identidade do operador.
resource "azurerm_role_assignment" "github_deploy_cluster_writer" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = azurerm_user_assigned_identity.github_deploy.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.aks_admin_principal_id
}

# ---------------------------------------------------------------------------
# Segredos de aplicacao: Key Vault + workload identity para o External
# Secrets Operator. Cada release tem UM segredo no vault, com um objeto JSON
# dentro; o ESO expande esse JSON nas chaves do Secret do Kubernetes. Assim
# acrescentar uma variavel de ambiente nao toca git nem CI.
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "apps" {
  name                       = var.key_vault_name
  resource_group_name        = azurerm_resource_group.aks.name
  location                   = azurerm_resource_group.aks.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # RBAC em vez de access policies: as permissoes ficam em role assignments,
  # junto com todas as outras deste arquivo.
  rbac_authorization_enabled = true

  tags = local.tags
}

# Voce escreve os segredos; o ESO so le.
resource "azurerm_role_assignment" "operator_key_vault_officer" {
  scope                = azurerm_key_vault.apps.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.aks_admin_principal_id
}

resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${var.cluster_name}-external-secrets"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "external_secrets_reader" {
  scope                = azurerm_key_vault.apps.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
  principal_type       = "ServicePrincipal"
}

# Workload identity: o ServiceAccount do ESO troca o token projetado do
# cluster por um token do Entra. Nenhum segredo de Azure vai para o cluster.
resource "azurerm_federated_identity_credential" "external_secrets" {
  name                      = "external-secrets-operator"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_secrets.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"
}

# ---------------------------------------------------------------------------
# Node pool dedicado do ZISP
#
# Existe por tres razoes que se somam, nenhuma delas "organizacao":
#
#  1. o zisp-vpn-api monta /etc/ppp/chap-secrets por hostPath -- so funciona
#     no no que termina os tuneis L2TP;
#  2. o zisp-api precisa da rota para 10.19.24.0/22, que so existe nesse no;
#  3. Postgres e Redis do ZISP usam PVC Azure Disk, que e RWO e so monta onde
#     o disco esta anexado.
#
# O taint e a metade que importa: sem ele o scheduler poderia colocar o
# simplaca-api aqui e disputar a memoria do no da VPN. Com ele, so entra quem
# declara a toleration -- e so as releases do ZISP declaram.
#
# QUOTA: a quota regional de vCPU em eastus2 esta inteira consumida pelos dois
# nos do pool system (2 x Standard_D2as_v7 = 4 vCPU). Este pool NAO sobe antes
# de um aumento de quota aprovado, e e por isso que ele nasce desligado.
# Depois do aumento: zisp_node_pool_enabled = true no tfvars.
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "zisp" {
  count = var.zisp_node_pool_enabled ? 1 : 0

  name                  = "zisp"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.zisp_node_vm_size
  node_count            = 1
  auto_scaling_enabled  = false
  os_disk_size_gb       = 64
  vnet_subnet_id        = azurerm_subnet.nodes.id

  node_labels = {
    "byteflip.dev/workload" = "zisp"
  }

  # Formato chave=valor:efeito. Tem que casar exatamente com a toleration dos
  # values em apps/zisp/*/values-prod.yaml.
  node_taints = ["byteflip.dev/workload=zisp:NoSchedule"]

  upgrade_settings {
    max_surge = "10%"
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Credenciais federadas das aplicacoes ZISP
#
# O `subject` do token do GitHub e comparado como string LITERAL pelo Entra:
# nao ha curinga, entao e uma credencial por repo e por entrada. Build usa
# ref:refs/heads/main; deploy usa environment:production, que e o que faz o
# environment do GitHub valer como fronteira de verdade.
#
# Reaproveitar as identidades github_build/github_deploy do simplaca em vez de
# criar um par por produto e uma escolha com custo: o AcrPush e escopado no
# REGISTRY, nao por repositorio de imagem, logo o CI do zisp consegue
# sobrescrever a tag de uma imagem do simplaca. Para um operador unico o custo
# e aceitavel; com times separados, troque por identidade por produto + scope
# maps do ACR.
# ---------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "app_build" {
  for_each = var.github_app_repositories

  name                      = "github-${each.key}-build-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_build.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${each.value}:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "app_deploy" {
  for_each = var.github_app_repositories

  name                      = "github-${each.key}-deploy-prod"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${each.value}:environment:production"
}

# ---------------------------------------------------------------------------
# IP publico da VPN L2TP
#
# Declarado aqui, no NOSSO resource group, e nao deixado para o Service criar:
# um IP criado pelo Service morre com ele, e recriar o Service sortearia outro
# endereco -- o que significa visitar cada Mikrotik em campo outra vez. Esse e
# o tipo de custo que nao se paga duas vezes.
#
# Fica separado do IP do Traefik (135.18.210.136): aquele e HTTP/HTTPS, este e
# UDP 1701. Um Service nao compartilha frontend com o outro.
#
# Como o IP NAO esta no node resource group (MC_*), duas coisas sao
# necessarias, e falta de qualquer uma deixa o Service em <pending> sem erro
# claro:
#   1. a identidade do control plane precisa de Network Contributor nele;
#   2. o Service precisa da anotacao
#      service.beta.kubernetes.io/azure-load-balancer-resource-group
#      apontando para este RG (ver charts/vpn-server/values.yaml).
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "vpn" {
  name                = "${var.cluster_name}-vpn-l2tp"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location

  # Static, nao Dynamic: o endereco vai para a configuracao de cada CPE. Um IP
  # Dynamic muda e derruba todos os tuneis de uma vez.
  allocation_method = "Static"

  # Standard e obrigatorio: o load_balancer_sku do cluster e standard, e as
  # SKUs nao se misturam num mesmo Load Balancer.
  sku = "Standard"

  tags = local.tags
}

resource "azurerm_role_assignment" "aks_vpn_ip" {
  scope                = azurerm_public_ip.vpn.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
  principal_type       = "ServicePrincipal"
}
