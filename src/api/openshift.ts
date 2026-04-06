import { k8sGet, k8sListItems, type K8sResourceKind } from '@openshift-console/dynamic-plugin-sdk';
import type { K8sModel } from '@openshift-console/dynamic-plugin-sdk/lib/api/common-types';

/** OpenShift Project (project.openshift.io/v1) — list is RBAC-filtered for the logged-in user. */
export const ProjectModel: K8sModel = {
  abbr: 'PR',
  apiGroup: 'project.openshift.io',
  apiVersion: 'v1',
  kind: 'Project',
  label: 'Project',
  labelPlural: 'Projects',
  plural: 'projects',
  namespaced: false,
};

const ClusterVersionModel: K8sModel = {
  abbr: 'CV',
  apiGroup: 'config.openshift.io',
  apiVersion: 'v1',
  kind: 'ClusterVersion',
  label: 'ClusterVersion',
  labelPlural: 'ClusterVersions',
  plural: 'clusterversions',
  namespaced: false,
};

/** OpenShift Route — list without `ns` hits all namespaces (`GET /apis/route.openshift.io/v1/routes`). */
const RouteModel: K8sModel = {
  abbr: 'RT',
  apiGroup: 'route.openshift.io',
  apiVersion: 'v1',
  kind: 'Route',
  label: 'Route',
  labelPlural: 'Routes',
  plural: 'routes',
  namespaced: true,
};

/** Routes carrying this label identify namespaces eligible for the Enterprise Admin project list. */
export const RHEA_ADMIN_ROUTE_LABEL = { admin: 'rhea' } as const;

/**
 * Optional full URL override for the admin tab (otherwise derived from Route `spec.host`, TLS, and path).
 */
export const RHEA_CONSOLE_URL_ANNOTATION = 'rhea.redhat.com/console-url';

/** Optional tab title; falls back to `openshift.io/display-name` then Route name. */
export const RHEA_CONSOLE_DISPLAY_NAME_ANNOTATION = 'rhea.redhat.com/display-name';

type RouteForUrl = {
  metadata?: { annotations?: Record<string, string> };
  spec?: { host?: string; path?: string; tls?: Record<string, unknown> };
  status?: { ingress?: { host?: string }[] };
};

/** Public URL for a Route: annotation override, else `https?://host` + optional `spec.path`. */
export function routeAdminConsoleUrl(route: RouteForUrl): string | null {
  const ann = route.metadata?.annotations?.[RHEA_CONSOLE_URL_ANNOTATION]?.trim();
  if (ann) {
    return ann;
  }
  const host =
    (route.spec?.host ?? '').trim() || (route.status?.ingress?.[0]?.host ?? '').trim() || null;
  if (!host) {
    return null;
  }
  const scheme = route.spec?.tls ? 'https' : 'http';
  let path = (route.spec?.path ?? '').trim();
  if (path && !path.startsWith('/')) {
    path = `/${path}`;
  }
  return `${scheme}://${host}${path}`;
}

export type RheaAdminConsoleTab = {
  /** Stable id for React keys and ARIA (metadata.uid or namespace/name). */
  id: string;
  name: string;
  namespace: string;
  /** Tab label */
  label: string;
  /** From {@link routeAdminConsoleUrl} (annotation or Route host/path/TLS). */
  consoleUrl: string | null;
};

/**
 * Routes in `namespace` labeled `admin=rhea`, sorted by tab label.
 */
export async function listRheaAdminRoutesInNamespace(namespace: string): Promise<RheaAdminConsoleTab[]> {
  if (!namespace) {
    return [];
  }
  const items = await k8sListItems<RouteForUrl & {
    metadata?: {
      name?: string;
      namespace?: string;
      uid?: string;
      annotations?: Record<string, string>;
    };
  }>({
    model: RouteModel,
    queryParams: { ns: namespace, labelSelector: { ...RHEA_ADMIN_ROUTE_LABEL } },
  });
  const rows: RheaAdminConsoleTab[] = (items ?? [])
    .map((r) => {
      const name = r.metadata?.name;
      const ns = r.metadata?.namespace ?? namespace;
      if (!name) {
        return null;
      }
      const ann = r.metadata?.annotations ?? {};
      const label =
        (ann[RHEA_CONSOLE_DISPLAY_NAME_ANNOTATION] ?? '').trim() ||
        (ann['openshift.io/display-name'] ?? '').trim() ||
        name;
      const id = r.metadata?.uid ?? `${ns}/${name}`;
      return { id, name, namespace: ns, label, consoleUrl: routeAdminConsoleUrl(r) };
    })
    .filter((x): x is RheaAdminConsoleTab => x !== null);
  rows.sort((a, b) => a.label.localeCompare(b.label, undefined, { sensitivity: 'base' }));
  return rows;
}

export type ProjectSummary = {
  name: string;
  displayName: string;
};

function projectDisplayName(project: { metadata?: { name?: string; annotations?: Record<string, string> } }): string {
  const name = project.metadata?.name ?? '';
  const dn = project.metadata?.annotations?.['openshift.io/display-name'];
  return (dn && dn.trim()) || name;
}

/**
 * Projects the user can list that contain at least one Route labeled `admin=rhea`
 * (same auth/proxy as the console). Requires permission to list Routes cluster-wide.
 */
export async function listAccessibleProjects(): Promise<ProjectSummary[]> {
  const [projectItems, routeItems] = await Promise.all([
    k8sListItems<{ metadata?: { name?: string; annotations?: Record<string, string> } }>({
      model: ProjectModel,
      queryParams: {},
    }),
    k8sListItems<{ metadata?: { namespace?: string } }>({
      model: RouteModel,
      queryParams: { labelSelector: { ...RHEA_ADMIN_ROUTE_LABEL } },
    }),
  ]);

  const namespacesWithRheaAdminRoute = new Set<string>();
  for (const r of routeItems ?? []) {
    const ns = r.metadata?.namespace;
    if (ns) {
      namespacesWithRheaAdminRoute.add(ns);
    }
  }

  const rows: ProjectSummary[] = (projectItems ?? [])
    .map((p) => {
      const name = p.metadata?.name;
      if (!name || !namespacesWithRheaAdminRoute.has(name)) {
        return null;
      }
      return { name, displayName: projectDisplayName(p) };
    })
    .filter((x): x is ProjectSummary => x !== null);
  rows.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  return rows;
}

export type CurrentClusterOption = {
  /** Stable id for future multi-cluster; single cluster uses this constant. */
  value: string;
  label: string;
};

const CURRENT_CLUSTER_VALUE = 'current';

/**
 * Single entry representing the cluster hosting this console (multi-cluster later).
 */
export async function getCurrentClusterOption(): Promise<CurrentClusterOption> {
  try {
    const cv = await k8sGet<K8sResourceKind>({
      model: ClusterVersionModel,
      name: 'version',
    });
    const ver = cv?.status?.desired?.version;
    if (ver) {
      return { value: CURRENT_CLUSTER_VALUE, label: `This cluster (OpenShift ${ver})` };
    }
  } catch {
    // Missing get permission or CR not present — still offer a single cluster row.
  }
  return { value: CURRENT_CLUSTER_VALUE, label: 'This cluster' };
}

export { CURRENT_CLUSTER_VALUE };
