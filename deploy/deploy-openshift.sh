#!/usr/bin/env bash
#
# Build the console plugin image, push to the OpenShift internal registry,
# apply Deployment/Service + ConsolePlugin, and enable the plugin on the console.
#
# Prerequisites: oc login (short-lived token is fine), podman or docker.
#
# Override defaults with environment variables, e.g.:
#   NS=my-project TAG=v0.0.2 ./deploy/deploy-openshift.sh
#
set -euo pipefail

NS="${NS:-rhea-console-plugin}"
TAG="${TAG:-v0.0.1}"
IMAGE_NAME="${IMAGE_NAME:-rhea-enterprise-admin-plugin}"
PLUGIN_ID="${PLUGIN_ID:-rhea-enterprise-admin}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
PLATFORM="${PLATFORM:-linux/amd64}"
# On macOS + linux/amd64, default to host webpack + slim image (avoids QEMU hang during npm run build).
NODEJS_BUILD_ON_HOST="${NODEJS_BUILD_ON_HOST:-}"
if [[ -z "${NODEJS_BUILD_ON_HOST}" ]]; then
  if [[ "$(uname -s)" == "Darwin" && "${PLATFORM}" == "linux/amd64" ]]; then
    NODEJS_BUILD_ON_HOST=1
  else
    NODEJS_BUILD_ON_HOST=0
  fi
fi

SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_PUSH="${SKIP_PUSH:-0}"
SKIP_CONSOLE_PATCH="${SKIP_CONSOLE_PATCH:-0}"
# 1 = skip TLS verify for registry login/push (self-signed / private CA). Set 0 for public or corporate CA.
REGISTRY_TLS_VERIFY_INSECURE="${REGISTRY_TLS_VERIFY_INSECURE:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Build, push, and deploy the rhea-enterprise-admin OpenShift console plugin.

Usage: $0 [--help]

Environment variables:
  NS                  Target namespace (default: rhea-console-plugin)
  TAG                 Image tag (default: v0.0.1)
  IMAGE_NAME          Image name component (default: rhea-enterprise-admin-plugin)
  PLUGIN_ID           Console plugin name / metadata.name (default: rhea-enterprise-admin)
  CONTAINER_ENGINE    podman or docker (default: podman)
  PLATFORM            linux/amd64 (default) or linux/arm64 — match your cluster; on Mac M*, amd64 is emulated
  SKIP_BUILD=1        Skip image build (use existing local tag)
  SKIP_PUSH=1         Skip registry login + push
  SKIP_CONSOLE_PATCH=1  Do not patch consoles.operator.openshift.io (apply manifests only)
  NODEJS_BUILD_ON_HOST=0  Force in-container webpack (default on Mac+amd64 is 1 = host npm run build + Dockerfile.dist-only)
  REGISTRY_TLS_VERIFY_INSECURE  1 (default) = podman login/push --tls-verify=false; 0 = strict TLS

Registry login uses: oc registry login (recommended). If that fails, falls back to podman + token.
You need a token in kubeconfig: oc login --token=... (client-cert-only oc sessions cannot push).

To apply YAML only (no build/push): ./deploy/setup-cluster.sh or ./deploy/apply-manifests.sh
To remove the plugin: ./deploy/cleanup-cluster.sh
If pods are 0/1 or the plugin shows disabled: ./deploy/diagnose-plugin.sh then ./deploy/setup-cluster.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

require_cmd oc
require_cmd sed
require_cmd "${CONTAINER_ENGINE}"
if [[ "${NODEJS_BUILD_ON_HOST}" == "1" ]]; then
  require_cmd node
  require_cmd npm
fi

if ! oc whoami >/dev/null 2>&1; then
  echo "error: not logged in; run: oc login --token=... --server=..." >&2
  exit 1
fi

EXTERNAL_REGISTRY="$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || true)"
if [[ -z "${EXTERNAL_REGISTRY}" ]]; then
  echo "error: could not read image registry route (namespace openshift-image-registry, route default-route)." >&2
  exit 1
fi

EXTERNAL_IMAGE="${EXTERNAL_REGISTRY}/${NS}/${IMAGE_NAME}:${TAG}"
INTERNAL_IMAGE="image-registry.openshift-image-registry.svc:5000/${NS}/${IMAGE_NAME}:${TAG}"

log "Using namespace=${NS} tag=${TAG}"
log "External image (build/push): ${EXTERNAL_IMAGE}"
log "Internal image (Deployment): ${INTERNAL_IMAGE}"
if [[ "${REGISTRY_TLS_VERIFY_INSECURE}" == "1" ]]; then
  log "Registry TLS verification disabled for login/push (REGISTRY_TLS_VERIFY_INSECURE=1). Set to 0 if the registry uses a trusted CA."
fi

if [[ "${NODEJS_BUILD_ON_HOST}" == "1" ]]; then
  log "Host-side webpack + Dockerfile.dist-only (avoids QEMU during production build; image stays --platform ${PLATFORM})."
elif [[ "$(uname -s)" == "Darwin" && "${PLATFORM}" == "linux/amd64" ]]; then
  log "WARNING: in-container webpack under linux/amd64 QEMU on Apple Silicon can take 30+ min or look hung."
  log "Set NODEJS_BUILD_ON_HOST=1 (default on Darwin+amd64) or PLATFORM=linux/arm64 for ARM clusters."
fi

if ! oc get namespace "${NS}" >/dev/null 2>&1; then
  log "Creating namespace ${NS}"
  oc new-project "${NS}"
else
  oc project "${NS}" >/dev/null
fi

if [[ "${SKIP_BUILD}" != "1" ]]; then
  log "Building image (${CONTAINER_ENGINE}, ${PLATFORM})"
  (
    cd "${ROOT_DIR}"
    if [[ "${NODEJS_BUILD_ON_HOST}" == "1" ]]; then
      log "npm ci && npm run build (host)"
      npm ci
      NODE_ENV=production npm run build
      if [[ ! -f dist/plugin-manifest.json ]]; then
        echo "error: dist/plugin-manifest.json missing after npm run build" >&2
        exit 1
      fi
      "${CONTAINER_ENGINE}" build --platform "${PLATFORM}" -t "${EXTERNAL_IMAGE}" -f Dockerfile.dist-only .
    else
      "${CONTAINER_ENGINE}" build --platform "${PLATFORM}" -t "${EXTERNAL_IMAGE}" -f Dockerfile .
    fi
  )
else
  log "Skipping build (SKIP_BUILD=1)"
fi

if [[ "${SKIP_PUSH}" != "1" ]]; then
  REGISTRY_TLS_OPTS=()
  if [[ "${REGISTRY_TLS_VERIFY_INSECURE}" == "1" ]]; then
    case "${CONTAINER_ENGINE}" in
      podman)
        REGISTRY_TLS_OPTS=(--tls-verify=false)
        ;;
      docker)
        echo "error: docker does not support --tls-verify=false on login/push. Use CONTAINER_ENGINE=podman, or add this registry to \"insecure-registries\" in Docker Engine." >&2
        exit 1
        ;;
      *)
        echo "error: unknown CONTAINER_ENGINE=${CONTAINER_ENGINE}" >&2
        exit 1
        ;;
    esac
  fi

  log "Logging in to registry ${EXTERNAL_REGISTRY}"
  # Prefer oc registry login: stores kubeconfig token in the format registries expect (avoids -p token/shell issues).
  OC_REG_ARGS=(--registry="${EXTERNAL_REGISTRY}")
  if [[ "${REGISTRY_TLS_VERIFY_INSECURE}" == "1" ]]; then
    OC_REG_ARGS+=(--insecure=true)
  fi
  if oc registry login "${OC_REG_ARGS[@]}"; then
    log "Registry credentials stored (oc registry login)"
  else
    OC_TOKEN="$(oc whoami -t 2>/dev/null || true)"
    if [[ -z "${OC_TOKEN}" ]]; then
      echo "error: no OAuth token in kubeconfig (oc whoami -t is empty). Client-cert-only logins cannot push to the integrated registry." >&2
      echo "  Fix: oc login --token=... (copy from web console) then re-run this script." >&2
      exit 1
    fi
    log "oc registry login failed; falling back to ${CONTAINER_ENGINE} login with --password-stdin"
    printf '%s' "${OC_TOKEN}" | "${CONTAINER_ENGINE}" login "${REGISTRY_TLS_OPTS[@]}" -u "$(oc whoami)" --password-stdin "${EXTERNAL_REGISTRY}"
  fi

  log "Pushing ${EXTERNAL_IMAGE}"
  "${CONTAINER_ENGINE}" push "${REGISTRY_TLS_OPTS[@]}" "${EXTERNAL_IMAGE}"
else
  log "Skipping push (SKIP_PUSH=1)"
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

log "Applying nginx ConfigMap (HTTPS :8443 for console proxy; HTTP :8080 for probes)"
oc create configmap rhea-enterprise-admin-plugin-nginx \
  --from-file=nginx.conf="${SCRIPT_DIR}/nginx.conf" \
  -n "${NS}" --dry-run=client -o yaml | oc apply -f -

log "Applying Service + Deployment (Service annotation requests serving cert Secret)"
render_deployment | oc apply -f -

log "Waiting for Service Serving Certificate Secret rhea-plugin-serving-cert (up to ~3 min)"
SECRET_READY=0
for _ in $(seq 1 90); do
  if oc get secret rhea-plugin-serving-cert -n "${NS}" >/dev/null 2>&1; then
    SECRET_READY=1
    break
  fi
  sleep 2
done
if [[ "${SECRET_READY}" -eq 1 ]]; then
  log "Serving cert secret found; rolling pods so volume mounts succeed"
  oc rollout restart deployment/rhea-enterprise-admin-plugin -n "${NS}" >/dev/null 2>&1 || true
else
  echo "warning: Secret rhea-plugin-serving-cert not yet created. If pods are CreateContainerConfigError, wait and run:" >&2
  echo "  oc rollout restart deployment/rhea-enterprise-admin-plugin -n ${NS}" >&2
fi

log "Applying ConsolePlugin"
render_consoleplugin | oc apply -f -

log "Waiting for deployment rollout"
oc rollout status "deployment/rhea-enterprise-admin-plugin" -n "${NS}" --timeout=300s

log "Waiting for at least one Ready plugin pod (readiness uses GET /plugin-manifest.json)"
if ! oc wait pod -n "${NS}" -l app=rhea-enterprise-admin-plugin --for=condition=Ready --timeout=180s 2>/dev/null; then
  echo "warning: no pod reached Ready in time — describe pods for ImagePullBackOff / CrashLoop / probe failures:" >&2
  oc get pods -n "${NS}" -l app=rhea-enterprise-admin-plugin -o wide >&2 || true
  oc describe pod -n "${NS}" -l app=rhea-enterprise-admin-plugin 2>&1 | tail -80 >&2 || true
fi

PLUGIN_POD="$(
  oc get pods -n "${NS}" -l 'app=rhea-enterprise-admin-plugin' \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | head -1
)"
HTTP_CODE="000"
PROBE_ERR_FILE="$(mktemp)"
cleanup_probe_err() {
  rm -f "${PROBE_ERR_FILE}"
}
trap cleanup_probe_err EXIT

if [[ -z "${PLUGIN_POD}" ]]; then
  echo "warning: no Running pod with label app=rhea-enterprise-admin-plugin; cannot probe manifest." >&2
else
  # Do not hide stderr: 000 often means curl could not connect or oc exec was denied.
  set +e
  HTTP_CODE="$(
    oc exec -n "${NS}" "${PLUGIN_POD}" -c console-plugin -- \
      curl -sS --connect-timeout 8 --max-time 15 -o /dev/null -w '%{http_code}' \
      'http://127.0.0.1:8080/plugin-manifest.json' 2>"${PROBE_ERR_FILE}"
  )"
  OC_EXEC_RC=$?
  set -e
  if [[ "${OC_EXEC_RC}" -ne 0 ]] || [[ ! "${HTTP_CODE}" =~ ^[0-9]{3}$ ]]; then
    echo "warning: manifest probe command failed (exit ${OC_EXEC_RC}), pod=${PLUGIN_POD}" >&2
    if [[ -s "${PROBE_ERR_FILE}" ]]; then
      echo "  oc exec / curl stderr:" >&2
      sed 's/^/  /' "${PROBE_ERR_FILE}" >&2
    fi
    HTTP_CODE="000"
  fi
fi

log "In-cluster GET http://127.0.0.1:8080/plugin-manifest.json -> HTTP ${HTTP_CODE} (expect 200)"
if [[ -n "${PLUGIN_POD}" ]]; then
  set +e
  HTTPS_CODE="$(
    oc exec -n "${NS}" "${PLUGIN_POD}" -c console-plugin -- \
      curl -sk --connect-timeout 8 --max-time 15 -o /dev/null -w '%{http_code}' \
      'https://127.0.0.1:8443/plugin-manifest.json' 2>/dev/null
  )"
  set -e
  log "In-cluster GET https://127.0.0.1:8443/plugin-manifest.json (TLS, -k) -> HTTP ${HTTPS_CODE:-000} (expect 200; console uses this port with Service CA)"
fi
if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "warning: HTTP manifest probe failed; console will show 'Failed to get a valid plugin manifest' until probes succeed." >&2
fi

if [[ "${SKIP_CONSOLE_PATCH}" == "1" ]]; then
  log "Skipping console operator patch (SKIP_CONSOLE_PATCH=1). Enable plugin manually in consoles.operator.openshift.io cluster."
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  log "Merging plugin into consoles.operator.openshift.io cluster spec.plugins"
  PLUGINS_JSON="$(
    oc get consoles.operator.openshift.io cluster -o json \
      | jq -c --arg p "${PLUGIN_ID}" '(.spec.plugins // []) + [$p] | unique'
  )"
  oc patch consoles.operator.openshift.io cluster --type=merge -p "{\"spec\":{\"plugins\":${PLUGINS_JSON}}}"
else
  echo "error: jq is required to merge spec.plugins. Install jq, or set SKIP_CONSOLE_PATCH=1 and run:" >&2
  echo "  oc patch consoles.operator.openshift.io cluster --type=merge -p '{\"spec\":{\"plugins\":[\"${PLUGIN_ID}\"]}}'" >&2
  echo "  (merge with any existing plugin names manually)" >&2
  exit 1
fi

log "Done. Refresh the OpenShift console; look under Administrator → Home for the plugin nav item."
log "Direct route path: /rhea-enterprise-admin (relative to console URL)."
