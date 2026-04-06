#!/usr/bin/env bash
#
# Remove the rhea-enterprise-admin console plugin from the cluster:
#   - Drop the plugin from consoles.operator.openshift.io cluster.spec.plugins
#   - Delete ConsolePlugin CR, Deployment, Service, ConfigMap, optional Secret
#   - Optionally delete the whole namespace (DELETE_NAMESPACE=1)
#
#   ./deploy/cleanup-cluster.sh
#   NS=my-ns PLUGIN_ID=rhea-enterprise-admin ./deploy/cleanup-cluster.sh
#   DELETE_NAMESPACE=1 ./deploy/cleanup-cluster.sh
#
set -euo pipefail

NS="${NS:-rhea-console-plugin}"
PLUGIN_ID="${PLUGIN_ID:-rhea-enterprise-admin}"
DELETE_NAMESPACE="${DELETE_NAMESPACE:-0}"
SKIP_CONSOLE_UNPATCH="${SKIP_CONSOLE_UNPATCH:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Remove the Rhea console plugin workload and unregister it from the console.

Usage: $0 [--help]

Environment:
  NS                     Namespace (default: rhea-console-plugin)
  PLUGIN_ID              ConsolePlugin name (default: rhea-enterprise-admin)
  DELETE_NAMESPACE=1     After removing resources, delete the project/namespace
  SKIP_CONSOLE_UNPATCH=1 Do not remove PLUGIN_ID from consoles.operator.openshift.io cluster.spec.plugins

Requires: oc login. Removing spec.plugins needs jq unless SKIP_CONSOLE_UNPATCH=1.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

if ! oc whoami >/dev/null 2>&1; then
  echo "error: not logged in; run: oc login ..." >&2
  exit 1
fi

if [[ "${SKIP_CONSOLE_UNPATCH}" != "1" ]]; then
  if command -v jq >/dev/null 2>&1; then
    log "Removing ${PLUGIN_ID} from consoles.operator.openshift.io cluster spec.plugins"
    PLUGINS_JSON="$(
      oc get consoles.operator.openshift.io cluster -o json \
        | jq -c --arg p "${PLUGIN_ID}" '(.spec.plugins // []) | map(select(. != $p))'
    )"
    oc patch consoles.operator.openshift.io cluster --type=merge -p "{\"spec\":{\"plugins\":${PLUGINS_JSON}}}"
  else
    echo "error: jq is required to edit spec.plugins. Install jq, or run with SKIP_CONSOLE_UNPATCH=1 and remove the plugin manually in Cluster Settings." >&2
    exit 1
  fi
else
  log "SKIP_CONSOLE_UNPATCH=1 — not changing consoles.operator.openshift.io cluster"
fi

log "Deleting ConsolePlugin ${PLUGIN_ID}"
oc delete consoleplugin "${PLUGIN_ID}" --ignore-not-found

if ! oc get namespace "${NS}" >/dev/null 2>&1; then
  log "Namespace ${NS} does not exist; nothing else to delete."
  exit 0
fi

log "Deleting workload in namespace ${NS}"
oc delete deployment rhea-enterprise-admin-plugin -n "${NS}" --ignore-not-found --wait=true --timeout=120s || true
oc delete service rhea-enterprise-admin-plugin -n "${NS}" --ignore-not-found
oc delete configmap rhea-enterprise-admin-plugin-nginx -n "${NS}" --ignore-not-found
oc delete secret rhea-plugin-serving-cert -n "${NS}" --ignore-not-found

if [[ "${DELETE_NAMESPACE}" == "1" ]]; then
  log "Deleting project/namespace ${NS}"
  oc delete project "${NS}" --wait=true
  log "Cleanup complete (namespace removed)."
else
  log "Cleanup complete. Namespace ${NS} still exists (set DELETE_NAMESPACE=1 to remove it)."
fi
