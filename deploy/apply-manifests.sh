#!/usr/bin/env bash
#
# Apply ConfigMap + Service + Deployment + ConsolePlugin (no build/push).
# Use this instead of hand-copying oc commands from chat (inline # comments break oc).
# Same behavior as ./deploy/setup-cluster.sh
#
#   ./deploy/apply-manifests.sh
#
#   NS=my-ns TAG=v0.0.2 ./deploy/apply-manifests.sh
#
set -euo pipefail

NS="${NS:-rhea-console-plugin}"
TAG="${TAG:-v0.0.1}"
IMAGE_NAME="${IMAGE_NAME:-rhea-enterprise-admin-plugin}"
PLUGIN_ID="${PLUGIN_ID:-rhea-enterprise-admin}"
SKIP_CONSOLE_PATCH="${SKIP_CONSOLE_PATCH:-0}"
INTERNAL_IMAGE="${INTERNAL_IMAGE:-image-registry.openshift-image-registry.svc:5000/${NS}/${IMAGE_NAME}:${TAG}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

if ! oc whoami >/dev/null 2>&1; then
  echo "error: not logged in; run: oc login ..." >&2
  exit 1
fi

if ! oc get namespace "${NS}" >/dev/null 2>&1; then
  log "Creating namespace ${NS}"
  oc new-project "${NS}"
else
  oc project "${NS}" >/dev/null
fi

render_deployment() {
  sed \
    -e "s/namespace: rhea-console-plugin/namespace: ${NS}/g" \
    -e "/image:/s|image:.*|image: ${INTERNAL_IMAGE}|" \
    "${SCRIPT_DIR}/deployment.yaml"
}

render_consoleplugin() {
  sed -e "s/namespace: rhea-console-plugin/namespace: ${NS}/g" "${SCRIPT_DIR}/consoleplugin.yaml"
}

log "Applying nginx ConfigMap"
oc create configmap rhea-enterprise-admin-plugin-nginx \
  --from-file=nginx.conf="${SCRIPT_DIR}/nginx.conf" \
  -n "${NS}" --dry-run=client -o yaml | oc apply -f -

log "Applying Service + Deployment (image ${INTERNAL_IMAGE})"
render_deployment | oc apply -f -

log "Waiting for serving cert Secret rhea-plugin-serving-cert"
SECRET_READY=0
for _ in $(seq 1 90); do
  if oc get secret rhea-plugin-serving-cert -n "${NS}" >/dev/null 2>&1; then
    SECRET_READY=1
    break
  fi
  sleep 2
done
if [[ "${SECRET_READY}" -eq 1 ]]; then
  log "Restarting deployment so TLS volume mounts"
  oc rollout restart deployment/rhea-enterprise-admin-plugin -n "${NS}" >/dev/null 2>&1 || true
else
  echo "warning: secret not ready yet; run later: oc rollout restart deployment/rhea-enterprise-admin-plugin -n ${NS}" >&2
fi

log "Applying ConsolePlugin"
render_consoleplugin | oc apply -f -

log "Rollout status"
oc rollout status deployment/rhea-enterprise-admin-plugin -n "${NS}" --timeout=300s

if [[ "${SKIP_CONSOLE_PATCH}" == "1" ]]; then
  log "SKIP_CONSOLE_PATCH=1; enable plugin in consoles.operator.openshift.io if needed."
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  log "Merging plugin into consoles.operator.openshift.io cluster spec.plugins"
  PLUGINS_JSON="$(
    oc get consoles.operator.openshift.io cluster -o json \
      | jq -c --arg p "${PLUGIN_ID}" '(.spec.plugins // []) + [$p] | unique'
  )"
  oc patch consoles.operator.openshift.io cluster --type=merge -p "{\"spec\":{\"plugins\":${PLUGINS_JSON}}}"
  log "Console spec.plugins is now: $(oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' 2>/dev/null || echo '?')"
else
  echo "error: install jq or set SKIP_CONSOLE_PATCH=1 and patch spec.plugins manually." >&2
  exit 1
fi

log "Done. If pods stay 0/1, run: ./deploy/diagnose-plugin.sh"
