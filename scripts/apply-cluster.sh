#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-personal-prod}"
ACTUAL_CONTEXT="$(kubectl config current-context)"
if [[ "$ACTUAL_CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
  echo "Expected kubectl context $EXPECTED_CONTEXT; found $ACTUAL_CONTEXT" >&2
  exit 1
fi

helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
helm repo update traefik >/dev/null

helm upgrade --install traefik traefik/traefik \
  --version 41.4.0 \
  --namespace traefik --create-namespace \
  --values "$ROOT/cluster/addons/traefik-values.yaml" \
  --atomic --wait --timeout 10m

helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.2 \
  --namespace cert-manager --create-namespace \
  --values "$ROOT/cluster/addons/cert-manager-values.yaml" \
  --atomic --wait --timeout 10m

kubectl apply -f "$ROOT/cluster/namespaces.yaml"
kubectl apply -f "$ROOT/cluster/issuers/letsencrypt-prod.yaml"
