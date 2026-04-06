#!/usr/bin/env bash
#
# Print plugin workload + console enablement state (run when pods are 0/1 or plugin shows disabled).
#
#   ./deploy/diagnose-plugin.sh
#   NS=my-ns ./deploy/diagnose-plugin.sh
#
set -euo pipefail

NS="${NS:-rhea-console-plugin}"
PLUGIN_ID="${PLUGIN_ID:-rhea-enterprise-admin}"

if ! oc whoami >/dev/null 2>&1; then
  echo "error: oc login required" >&2
  exit 1
fi

echo "=== consoles.operator.openshift.io cluster spec.plugins ==="
oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}{"\n"}' 2>/dev/null || echo "(not readable)"

echo ""
echo "=== ConsolePlugin ${PLUGIN_ID} ==="
oc get consoleplugin "${PLUGIN_ID}" -o wide 2>/dev/null || echo "(missing — apply deploy/consoleplugin.yaml)"

echo ""
echo "=== Pods (${NS}) ==="
oc get pods -n "${NS}" -l app=rhea-enterprise-admin-plugin -o wide 2>/dev/null || echo "(namespace missing?)"

echo ""
echo "=== Recent events (${NS}) ==="
oc get events -n "${NS}" --sort-by='.lastTimestamp' 2>/dev/null | tail -25 || true

echo ""
POD="$(oc get pods -n "${NS}" -l app=rhea-enterprise-admin-plugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${POD}" ]]; then
  echo "=== Pod status (${POD}) ==="
  oc get pod -n "${NS}" "${POD}" -o jsonpath='{.status.phase} {.status.containerStatuses[*].state} {.status.initContainerStatuses[*].state}{"\n"}' 2>/dev/null || true
  echo "--- conditions (reason/message) ---"
  oc get pod -n "${NS}" "${POD}" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason} {.message}{"\n"}{end}' 2>/dev/null || true
  echo ""
  echo "=== Init logs (${POD} wait-for-serving-cert) ==="
  oc logs -n "${NS}" "${POD}" -c wait-for-serving-cert 2>&1 | tail -40 || echo "(no init logs yet)"
  echo ""
  echo "=== Main container logs (${POD} console-plugin) ==="
  oc logs -n "${NS}" "${POD}" -c console-plugin 2>&1 | tail -40 || echo "(no main logs yet)"
  echo ""
fi

echo "=== Secret rhea-plugin-serving-cert (tls files must be non-empty) ==="
CRT_B64="$(oc get secret rhea-plugin-serving-cert -n "${NS}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)"
if [[ -n "${CRT_B64}" ]]; then
  echo "tls.crt key: present (${#CRT_B64} base64 chars)"
else
  echo "MISSING Secret or empty tls.crt — Service needs serving-cert annotations; wait for service-ca controller."
fi

echo ""
echo "=== Required objects ==="
for o in \
  "secret/rhea-plugin-serving-cert" \
  "configmap/rhea-enterprise-admin-plugin-nginx" \
  "service/rhea-enterprise-admin-plugin"; do
  if oc get -n "${NS}" "${o}" >/dev/null 2>&1; then
    echo "ok ${o}"
  else
    echo "MISSING ${o}"
  fi
done

echo ""
echo "If plugin is disabled: run ./deploy/setup-cluster.sh (needs jq) or add ${PLUGIN_ID} under Console spec.plugins."
echo "If init wait-for-serving-cert fails: ensure Service has service.beta.openshift.io/serving-cert-secret-name and wait for Secret."
