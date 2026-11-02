output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "resource_group_name" {
  value = azurerm_resource_group.aks.name
}

output "location" {
  value = azurerm_resource_group.aks.location
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

output "key_vault_name" {
  value = azurerm_key_vault.apps.name
}

output "external_secrets_client_id" {
  description = "Client ID the External Secrets ServiceAccount annotates for workload identity."
  value       = azurerm_user_assigned_identity.external_secrets.client_id
}

output "vpn_public_ip" {
  description = "Endereco que vai na configuracao L2TP de cada Mikrotik."
  value       = azurerm_public_ip.vpn.ip_address
}

output "vpn_service_values" {
  description = "Valores a passar para o release do charts/vpn-server."
  value = {
    loadBalancerIP            = azurerm_public_ip.vpn.ip_address
    loadBalancerResourceGroup = azurerm_resource_group.aks.name
  }
}
