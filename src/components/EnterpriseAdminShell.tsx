import * as React from 'react';
import { useTranslation } from 'react-i18next';
import { useActiveNamespace } from '@openshift-console/dynamic-plugin-sdk';
import {
  Alert,
  Button,
  FormSelect,
  FormSelectOption,
  PageSection,
  Spinner,
  Title,
} from '@patternfly/react-core';
import {
  CURRENT_CLUSTER_VALUE,
  getCurrentClusterOption,
  listAccessibleProjects,
  listRheaAdminRoutesInNamespace,
  RHEA_CONSOLE_URL_ANNOTATION,
  type ProjectSummary,
  type RheaAdminConsoleTab,
} from '../api/openshift';
import './enterprise-admin.css';

function routeTabDomId(tabId: string): string {
  return `rhea-admin-route-tab-${tabId.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
}

export default function EnterpriseAdminShell() {
  const { t } = useTranslation('plugin__rhea-enterprise-admin');
  const [activeNamespace] = useActiveNamespace();
  const [projects, setProjects] = React.useState<ProjectSummary[]>([]);
  const [projectsLoaded, setProjectsLoaded] = React.useState(false);
  const [projectsError, setProjectsError] = React.useState<string | null>(null);
  const [clusterLabel, setClusterLabel] = React.useState<string>('');
  const [project, setProject] = React.useState('');
  const [adminRoutes, setAdminRoutes] = React.useState<RheaAdminConsoleTab[]>([]);
  const [routesLoaded, setRoutesLoaded] = React.useState(false);
  const [routesError, setRoutesError] = React.useState<string | null>(null);
  const [activeRouteId, setActiveRouteId] = React.useState<string | null>(null);

  React.useEffect(() => {
    let cancelled = false;
    (async () => {
      setProjectsLoaded(false);
      setProjectsError(null);
      try {
        const plist = await listAccessibleProjects();
        if (cancelled) {
          return;
        }
        setProjects(plist);
        setProject((prev) => {
          if (prev && plist.some((p) => p.name === prev)) {
            return prev;
          }
          if (activeNamespace && plist.some((p) => p.name === activeNamespace)) {
            return activeNamespace;
          }
          return plist[0]?.name ?? '';
        });
      } catch (e) {
        if (!cancelled) {
          setProjects([]);
          setProjectsError(e instanceof Error ? e.message : String(e));
        }
      }
      try {
        const c = await getCurrentClusterOption();
        if (!cancelled) {
          setClusterLabel(c.label);
        }
      } catch {
        if (!cancelled) {
          setClusterLabel('This cluster');
        }
      } finally {
        if (!cancelled) {
          setProjectsLoaded(true);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [activeNamespace]);

  React.useEffect(() => {
    if (!project) {
      setAdminRoutes([]);
      setRoutesError(null);
      setRoutesLoaded(true);
      setActiveRouteId(null);
      return;
    }
    let cancelled = false;
    setRoutesLoaded(false);
    setRoutesError(null);
    (async () => {
      try {
        const list = await listRheaAdminRoutesInNamespace(project);
        if (cancelled) {
          return;
        }
        setAdminRoutes(list);
        setActiveRouteId((prev) => {
          if (prev && list.some((r) => r.id === prev)) {
            return prev;
          }
          return list[0]?.id ?? null;
        });
      } catch (e) {
        if (!cancelled) {
          setAdminRoutes([]);
          setActiveRouteId(null);
          setRoutesError(e instanceof Error ? e.message : String(e));
        }
      } finally {
        if (!cancelled) {
          setRoutesLoaded(true);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [project]);

  const selectedProject = projects.find((p) => p.name === project);
  const projectDisplay = selectedProject?.displayName || project || '—';
  const activeRoute = adminRoutes.find((r) => r.id === activeRouteId) ?? null;
  const activeTabDomId = activeRoute ? routeTabDomId(activeRoute.id) : 'rhea-admin-no-tab';

  return (
    <div className="rhea-enterprise-admin">
      <PageSection variant="default" className="rhea-enterprise-admin__masthead">
        <Title headingLevel="h1" size="2xl" className="rhea-enterprise-admin__brand-title">
          {t('pageTitle')}
        </Title>
      </PageSection>

      <PageSection variant="default" padding={{ default: 'noPadding' }}>
        <div
          className="rhea-enterprise-admin__product-tabs"
          role="tablist"
          aria-label={t('adminConsoleTabsAria')}
        >
          {!project || !routesLoaded ? (
            <button
              type="button"
              role="tab"
              aria-selected
              className="rhea-enterprise-admin__product-tab is-active is-placeholder"
              disabled
              id="rhea-admin-tab-loading"
            >
              {!project ? t('adminConsolesNoProject') : t('adminConsolesLoading')}
            </button>
          ) : routesError ? (
            <button
              type="button"
              role="tab"
              aria-selected
              className="rhea-enterprise-admin__product-tab is-active is-placeholder"
              disabled
              id="rhea-admin-tab-error"
            >
              {t('adminConsolesErrorTab')}
            </button>
          ) : adminRoutes.length === 0 ? (
            <button
              type="button"
              role="tab"
              aria-selected
              className="rhea-enterprise-admin__product-tab is-active is-placeholder"
              disabled
              id="rhea-admin-tab-empty"
            >
              {t('adminConsolesNoneInProject')}
            </button>
          ) : (
            adminRoutes.map((rt) => {
              const tid = routeTabDomId(rt.id);
              const isActive = rt.id === activeRouteId;
              return (
                <button
                  key={rt.id}
                  type="button"
                  role="tab"
                  aria-selected={isActive}
                  id={tid}
                  className={
                    isActive
                      ? 'rhea-enterprise-admin__product-tab is-active'
                      : 'rhea-enterprise-admin__product-tab'
                  }
                  onClick={() => setActiveRouteId(rt.id)}
                >
                  {rt.label}
                </button>
              );
            })
          )}
        </div>

        <div className="rhea-enterprise-admin__shell">
          <aside className="rhea-enterprise-admin__sidebar" aria-label={t('pageTitle')}>
            <div>
              {projectsError && (
                <Alert variant="danger" title={t('projectsError')} isInline className="rhea-enterprise-admin__alert">
                  {projectsError}
                </Alert>
              )}
              <div className="rhea-enterprise-admin__field-label">{t('clusterLabel')}</div>
              <FormSelect
                value={CURRENT_CLUSTER_VALUE}
                onChange={() => undefined}
                aria-label={t('clusterLabel')}
                ouiaId="rhea-cluster"
                isDisabled
              >
                <FormSelectOption
                  value={CURRENT_CLUSTER_VALUE}
                  label={clusterLabel || t('projectsLoading')}
                />
              </FormSelect>
              <div className="rhea-enterprise-admin__field-label rhea-enterprise-admin__field-label--with-spinner">
                <span>{t('projectLabel')}</span>
                {!projectsLoaded && (
                  <Spinner size="sm" aria-label={t('projectsLoading')} className="rhea-enterprise-admin__spinner" />
                )}
              </div>
              <FormSelect
                value={project}
                onChange={(_e, val) => setProject(val)}
                aria-label={t('projectLabel')}
                ouiaId="rhea-project"
                isDisabled={!projectsLoaded || projects.length === 0}
              >
                {projects.length === 0 ? (
                  <FormSelectOption value="" label={t('noProjects')} isDisabled />
                ) : (
                  projects.map((p) => (
                    <FormSelectOption
                      key={p.name}
                      value={p.name}
                      label={p.displayName !== p.name ? `${p.displayName} (${p.name})` : p.name}
                    />
                  ))
                )}
              </FormSelect>
            </div>
            <div className="rhea-enterprise-admin__sidebar-actions">
              <Button variant="secondary" className="rhea-enterprise-admin__sidebar-btn" isBlock>
                {t('systemSettings')}
              </Button>
              <Button variant="secondary" className="rhea-enterprise-admin__sidebar-btn" isBlock>
                {t('accountOverview')}
              </Button>
              <Button variant="secondary" className="rhea-enterprise-admin__sidebar-btn" isBlock>
                {t('acl')}
              </Button>
            </div>
          </aside>

          <div className="rhea-enterprise-admin__main" role="tabpanel" aria-labelledby={activeTabDomId}>
            {!project ? (
              <div className="rhea-enterprise-admin__console-empty">
                <Title headingLevel="h2" size="lg">
                  {t('adminConsolesPickProjectTitle')}
                </Title>
                <p className="rhea-enterprise-admin__console-empty-desc">{t('adminConsolesPickProjectBody')}</p>
              </div>
            ) : !routesLoaded ? (
              <div className="rhea-enterprise-admin__console-loading">
                <Spinner size="lg" aria-label={t('adminConsolesLoading')} />
                <span className="rhea-enterprise-admin__console-loading-text">{t('adminConsolesLoading')}</span>
              </div>
            ) : routesError ? (
              <Alert variant="danger" title={t('adminConsolesLoadFailedTitle')} isInline>
                {routesError}
              </Alert>
            ) : adminRoutes.length === 0 ? (
              <div className="rhea-enterprise-admin__console-empty">
                <Title headingLevel="h2" size="lg">
                  {t('adminConsolesNoneInProjectTitle', { project: projectDisplay })}
                </Title>
                <p className="rhea-enterprise-admin__console-empty-desc">{t('adminConsolesNoneInProjectBody')}</p>
              </div>
            ) : (
              <AdminConsolePanel tab={activeRoute} annotationKey={RHEA_CONSOLE_URL_ANNOTATION} t={t} />
            )}
          </div>
        </div>
      </PageSection>
    </div>
  );
}

type Translate = (key: string, options?: Record<string, string>) => string;

function AdminConsolePanel({
  tab,
  annotationKey,
  t,
}: {
  tab: RheaAdminConsoleTab | null;
  annotationKey: string;
  t: Translate;
}) {
  if (!tab) {
    return (
      <div className="rhea-enterprise-admin__console-empty">
        <p>{t('adminConsolesSelectTab')}</p>
      </div>
    );
  }

  if (!tab.consoleUrl) {
    return (
      <div className="rhea-enterprise-admin__console-empty">
        <Alert variant="warning" title={t('consoleNoUrlTitle', { name: tab.name })} isInline>
          <p>{t('consoleNoUrlBody', { annotation: annotationKey })}</p>
        </Alert>
      </div>
    );
  }

  return (
    <div className="rhea-enterprise-admin__console">
      <div className="rhea-enterprise-admin__console-toolbar">
        <span className="rhea-enterprise-admin__console-service-meta">
          {t('adminConsoleEmbedding', { label: tab.label, namespace: tab.namespace })}
        </span>
        <Button
          variant="link"
          component="a"
          href={tab.consoleUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="rhea-enterprise-admin__console-open-link"
        >
          {t('openConsoleInNewWindow')}
        </Button>
      </div>
      <iframe
        title={tab.label}
        src={tab.consoleUrl}
        className="rhea-enterprise-admin__console-iframe"
        sandbox="allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox allow-modals"
        referrerPolicy="strict-origin-when-cross-origin"
      />
    </div>
  );
}
