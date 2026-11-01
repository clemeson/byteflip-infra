#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT="${1:?usage: deploy-app.sh <product> <component> <image-repository> <full-commit-sha>}"
COMPONENT="${2:?missing component}"
IMAGE_REPOSITORY="${3:?missing image repository}"
IMAGE_TAG="${4:?missing image tag}"

if [[ ! "$IMAGE_TAG" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Image tag must be a full 40-character lowercase commit SHA" >&2
  exit 1
fi

VALUES="$ROOT/apps/$PRODUCT/$COMPONENT/values-prod.yaml"
if [[ ! -f "$VALUES" ]]; then
  echo "No values file: $VALUES" >&2
  exit 1
fi

EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-personal-prod}"
ACTUAL_CONTEXT="$(kubectl config current-context)"
if [[ "$ACTUAL_CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
  echo "Expected kubectl context $EXPECTED_CONTEXT; found $ACTUAL_CONTEXT" >&2
  exit 1
fi

RELEASE="$PRODUCT-$COMPONENT"
helm upgrade --install "$RELEASE" "$ROOT/charts/app" \
  --namespace "$PRODUCT" \
  --values "$VALUES" \
  --set-string "image.repository=$IMAGE_REPOSITORY" \
  --set-string "image.tag=$IMAGE_TAG" \
  --set-string "deployNonce=${DEPLOY_NONCE:-}" \
  --atomic --wait --timeout 10m --history-max 20

helm status "$RELEASE" --namespace "$PRODUCT"
