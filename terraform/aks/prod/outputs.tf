output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "resource_group_name" {
  value = azurerm_resource_group.aks.name
}

output "acr_resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "github_build_client_id" {
  value = azurerm_user_assigned_identity.github_build.client_id
}

output "github_deploy_client_id" {
  value = azurerm_user_assigned_identity.github_deploy.client_id
}

output "azure_tenant_id" {
  value = azurerm_user_assigned_identity.github_build.tenant_id
}

output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.main.name}"
}
