# Rhea — Enterprise Administrator (OpenShift Console Dynamic Plugin)

OpenShift **dynamic console plugin** that adds an **Enterprise Administrator** page under the **Administrator** perspective. It lists **projects** the user can access that contain at least one **Route** labeled `admin=rhea`, and shows **one tab per matching Route** in the selected project. Each tab embeds the app’s admin UI in an **iframe** (with an **Open in new window** link).

The plugin talks to the cluster through the same APIs as the rest of the console (`k8sListItems`, `k8sGet` from `@openshift-console/dynamic-plugin-sdk`), so your OpenShift RBAC applies.

## Requirements

- OpenShift 4.x with the **dynamic plugin** stack enabled
- Console / plugin API aligned with **`@openshift-console/dynamic-plugin-sdk`** `4.20-latest` (see `package.json`)
- Users need permission to **list Projects**, **list Routes** (cluster-wide for the project dropdown, and in each namespace for tabs), and **get** `ClusterVersion` named `version` (optional, for cluster label text)

## How routing and URLs work

| Mechanism | Purpose |
|-----------|---------|
| Label **`admin=rhea`** on a **Route** | Namespace appears in the project list; Route appears as a tab when that project is selected |
| **`spec.host`** (+ optional **`status.ingress[0].host`**) | Used to build the console URL if no override annotation is set |
| **`spec.tls`** | If present, URL scheme is **https**; otherwise **http** |
| **`spec.path`** | Appended to the host (normalized with a leading `/`) |
| Annotation **`rhea.redhat.com/console-url`** | Optional **full URL** override (e.g. external URL) |
| Annotation **`rhea.redhat.com/display-name`** | Optional **tab title**; then `openshift.io/display-name`; then Route **metadata.name** |

URL construction is implemented in `routeAdminConsoleUrl()` in [`src/api/openshift.ts`](src/api/openshift.ts).

### Example Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: grafana-admin
  namespace: my-team-observability
  labels:
    admin: rhea
  annotations:
    rhea.redhat.com/display-name: "Grafana"
    # Optional if spec.host/path/tls are not what you need in the iframe:
    # rhea.redhat.com/console-url: "https://grafana.example.com"
spec:
  host: grafana-my-team-observability.apps.cluster.example.com
  tls:
    termination: edge
  to:
    kind: Service
    name: grafana
  wildcardPolicy: None
```

## UI entry points

- **Console path:** `/rhea-enterprise-admin`
- **Navigation:** Administrator → **Enterprise Administrator** (label from i18n `navLabel`)

Extensions are declared in [`console-extensions.json`](console-extensions.json).

## Local development

```bash
npm install
npm run build        # production assets → dist/
npm run build-dev    # non-minified build
npm start            # RHEA_PREVIEW=1: webpack dev server + shell-only preview (no real cluster APIs)
```

The preview shell renders [`EnterpriseAdminShell`](src/components/EnterpriseAdminShell.tsx) without the full console host; **Kubernetes calls will not work** there. Validate against a real cluster after deploying the plugin.

## Deploy on OpenShift

Scripts live under [`deploy/`](deploy/).

### Full build, push, and enable

Requires `oc login`, **podman** or **docker**, and registry access (often `oc registry login`).

```bash
./deploy/deploy-openshift.sh
```

Useful overrides (see script `--help`):

- `NS` — target namespace (default `rhea-console-plugin`)
- `TAG` — image tag (default `v0.0.1`)
- `SKIP_CONSOLE_PATCH=1` — apply manifests only, do not patch `consoles.operator.openshift.io`
- `NODEJS_BUILD_ON_HOST=1` — on macOS + `linux/amd64`, host `npm run build` + slim image (default behavior there)

### Apply manifests only (image already in registry)

If the image is already built and pushed to the internal registry:

```bash
./deploy/apply-manifests.sh
# or with overrides:
NS=my-ns TAG=v0.0.2 ./deploy/apply-manifests.sh
```

### Cleanup and diagnostics

- [`deploy/cleanup-cluster.sh`](deploy/cleanup-cluster.sh) — remove plugin-related resources
- [`deploy/diagnose-plugin.sh`](deploy/diagnose-plugin.sh) — troubleshoot TLS, serving cert, and plugin availability

The [`ConsolePlugin`](deploy/consoleplugin.yaml) resource points the console at the plugin **Service** on port **8443** (HTTPS with Service Serving Certificate).

## Project layout (high level)

| Path | Role |
|------|------|
| `src/components/EnterpriseAdminShell.tsx` | Main UI: cluster/project pickers, dynamic tabs, iframe |
| `src/api/openshift.ts` | Projects, Routes, cluster version, URL helpers |
| `locales/en/plugin__rhea-enterprise-admin.json` | English strings |
| `webpack.config.cjs` | Plugin bundle + federated modules |
| `deploy/` | Container image, Deployment, Service, ConsolePlugin, scripts |

## Iframe and security notes

Many UIs send **`X-Frame-Options`** or **`Content-Security-Policy: frame-ancestors`** and **will not render inside an iframe**. The **Open in new window** link should still work. To embed successfully, the target app (or a reverse proxy) must allow framing from your console origin.

The iframe uses a restrictive **`sandbox`**; adjust only if you understand the security tradeoffs.

## License

Apache-2.0 (see `package.json`).
