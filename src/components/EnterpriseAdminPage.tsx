import { DocumentTitle } from '@openshift-console/dynamic-plugin-sdk';
import { useTranslation } from 'react-i18next';
import EnterpriseAdminShell from './EnterpriseAdminShell';

export default function EnterpriseAdminPage() {
  const { t } = useTranslation('plugin__rhea-enterprise-admin');
  return (
    <>
      <DocumentTitle>{t('pageTitle')}</DocumentTitle>
      <EnterpriseAdminShell />
    </>
  );
}
