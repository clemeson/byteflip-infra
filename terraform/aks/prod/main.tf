locals {
  tags = {
    ManagedBy   = "terraform"
    Environment = "prod"
    Project     = "cluster_byteflip"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "aks" {
  name     = var.aks_resource_group_name
  location = var.aks_location
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
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_user_assigned_identity" "github_build" {
  name                = "${var.cluster_name}-github-build"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
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
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github_deploy" {
  name                      = "github-simplaca-deploy-prod"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_simplaca_repository}:environment:production"
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

resource "azurerm_role_assignment" "github_deploy_simplaca_writer" {
  scope                = "${azurerm_kubernetes_cluster.main.id}/namespaces/simplaca"
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = azurerm_user_assigned_identity.github_deploy.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.aks_admin_principal_id
}
