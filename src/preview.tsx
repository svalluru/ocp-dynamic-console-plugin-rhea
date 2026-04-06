/**
 * Local browser preview only. OpenShift Console loads the plugin via module federation;
 * it does not serve a standalone HTML app at /.
 */
import '@patternfly/react-core/dist/styles/base.css';
import * as ReactDOM from 'react-dom';
import i18n from 'i18next';
import { I18nextProvider, initReactI18next } from 'react-i18next';
import EnterpriseAdminShell from './components/EnterpriseAdminShell';
import locale from '../locales/en/plugin__rhea-enterprise-admin.json';

const rootEl = document.getElementById('root');
if (!rootEl) {
  // eslint-disable-next-line no-console
  console.error('rhea preview: missing #root');
} else {
  void i18n
    .use(initReactI18next)
    .init({
      lng: 'en',
      fallbackLng: 'en',
      interpolation: { escapeValue: false },
      react: { useSuspense: false },
      resources: {
        en: { 'plugin__rhea-enterprise-admin': locale },
      },
    })
    .then(() => {
      ReactDOM.render(
        <I18nextProvider i18n={i18n}>
          <EnterpriseAdminShell />
        </I18nextProvider>,
        rootEl,
      );
    })
    .catch((err: unknown) => {
      // eslint-disable-next-line no-console
      console.error('rhea preview: i18n init failed', err);
    });
}
