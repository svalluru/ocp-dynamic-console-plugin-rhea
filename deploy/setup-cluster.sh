#!/usr/bin/env bash
#
# Install / refresh the console plugin on the cluster (manifests + Console enablement).
# Does not build or push images — use deploy-openshift.sh for a full image build + deploy.
#
#   ./deploy/setup-cluster.sh
#   NS=my-ns TAG=v0.0.2 ./deploy/setup-cluster.sh
#   SKIP_CONSOLE_PATCH=1 ./deploy/setup-cluster.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Apply ConfigMap, Service, Deployment, ConsolePlugin, and enable the plugin on the console.

Usage: $0 [--help]

This script runs apply-manifests.sh. Environment variables are passed through unchanged, e.g.:
  NS, TAG, IMAGE_NAME, PLUGIN_ID, INTERNAL_IMAGE, SKIP_CONSOLE_PATCH

For build + push + deploy, use:
  ./deploy/deploy-openshift.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

exec "${SCRIPT_DIR}/apply-manifests.sh"
