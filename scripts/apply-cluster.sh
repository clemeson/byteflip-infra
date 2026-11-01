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
: "${ACME_EMAIL:?Set ACME_EMAIL to the ACME contact address}"
python3 - "$ROOT/cluster/issuers/letsencrypt-prod.yaml" <<'PY' | kubectl apply -f -
import json
import os
from pathlib import Path
import sys

manifest = Path(sys.argv[1]).read_text()
email = os.environ["ACME_EMAIL"]
if manifest.count("  acme:\n") != 1:
    raise SystemExit("Expected exactly one ACME configuration in ClusterIssuer")
print(manifest.replace("  acme:\n", "  acme:\n    email: " + json.dumps(email) + "\n", 1))
PY
