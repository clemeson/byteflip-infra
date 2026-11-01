output "traefik_public_ip" {
  description = "Public IP of the Traefik load balancer. Point the API A record here."
  value       = try(data.kubernetes_service.traefik.status[0].load_balancer[0].ingress[0].ip, "pending")
}

output "application_namespaces" {
  description = "Namespaces created for application releases."
  value       = sort([for ns in kubernetes_namespace.applications : ns.metadata[0].name])
}

output "installed_versions" {
  description = "Pinned add-on chart versions currently applied."
  value = {
    traefik      = helm_release.traefik.version
    cert_manager = helm_release.cert_manager.version
  }
}
