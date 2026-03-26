import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsOptionGroup,
  SettingsScreenContainer,
  SettingsSectionTitle,
} from '../../../src/features/settings/SettingsUI';
import {
  fetchAutumnCustomer,
  hasAutumnProAccess,
  openAutumnBillingPortal,
  startAutumnCheckout,
} from '../../../src/shared/integrations/autumn';
import { ActivityIndicator, Alert, Linking, StyleSheet, Text, View } from 'react-native';
import { captureEvent } from '../../../src/shared/telemetry/posthog';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { sessionAtom } from '../../../src/shared/state/session';
import { getNativeEnv } from '../../../src/shared/config/env';
import { useMutation, useQuery } from '@tanstack/react-query';
import { typography } from '@zero/design-tokens';
import { useMemo, useState } from 'react';
import { useAtomValue } from 'jotai';

type BillingCycle = 'monthly' | 'annual';

const PRODUCT_BY_CYCLE: Record<BillingCycle, string> = {
  monthly: 'pro-example',
  annual: 'pro_annual',
};

const FEATURE_LABELS: Record<string, string> = {
  'chat-messages': 'AI Chat Messages',
  connections: 'Email Connections',
  'brain-activity': 'Brain Activity',
};

function formatFeatureName(featureId: string): string {
  return FEATURE_LABELS[featureId] ?? featureId.replace(/-/g, ' ');
}

function formatFeatureBalance(feature: {
  unlimited?: boolean | null;
  balance?: number | null;
  usage?: number | null;
  included_usage?: number | null;
}): string {
  if (feature.unlimited) return 'Unlimited';

  const remaining = typeof feature.balance === 'number' ? feature.balance : null;
  const total = typeof feature.included_usage === 'number' ? feature.included_usage : null;
  if (remaining !== null && total !== null && total > 0) {
    return `${remaining} remaining`;
  }
  if (remaining !== null) {
    return `${remaining} remaining`;
  }
  if (typeof feature.usage === 'number') {
    return `${feature.usage} used`;
  }
  return 'Not available';
}

export default function BillingSettings() {
  const { colors, ui } = useTheme();
  const env = getNativeEnv();
  const session = useAtomValue(sessionAtom);
  const [cycle, setCycle] = useState<BillingCycle>('monthly');
  const bearerToken = session?.mode === 'bearer' ? session.token : null;
  const billingEnabled = Boolean(bearerToken) && !env.authBypassEnabled;

  const customerQuery = useQuery({
    queryKey: ['autumn', 'customer'],
    enabled: billingEnabled,
    queryFn: () => fetchAutumnCustomer(env.backendUrl, bearerToken!),
  });

  const customer = customerQuery.data;
  const isPro = hasAutumnProAccess(customer);

  const featureRows = useMemo(() => {
    const features = customer?.features ?? {};
    return Object.entries(features).map(([featureId, feature]) => ({
      id: featureId,
      label: formatFeatureName(featureId),
      value: formatFeatureBalance(feature),
    }));
  }, [customer?.features]);

  const openPricingOnWeb = async () => {
    const url = `${env.webUrl.replace(/\/$/, '')}/mail/inbox?pricingDialog=true`;
    await Linking.openURL(url);
  };

  const billingPortalMutation = useMutation({
    mutationFn: () => openAutumnBillingPortal(env.backendUrl, bearerToken!),
    onSuccess: async (url) => {
      captureEvent('billing_portal_opened', {
        source: 'native_settings_billing',
      });
      await Linking.openURL(url);
    },
    onError: async (error: any) => {
      Alert.alert(
        'Could not open billing portal',
        error?.message || 'Open billing in web settings instead?',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Open Web',
            onPress: () => {
              void openPricingOnWeb();
            },
          },
        ],
      );
    },
  });

  const upgradeMutation = useMutation({
    mutationFn: () =>
      startAutumnCheckout(env.backendUrl, bearerToken!, {
        productId: PRODUCT_BY_CYCLE[cycle],
        successUrl: `${env.webUrl.replace(/\/$/, '')}/mail/inbox?success=true`,
      }),
    onSuccess: async (url) => {
      captureEvent('billing_upgrade_started', {
        source: 'native_settings_billing',
        billing_cycle: cycle,
        product_id: PRODUCT_BY_CYCLE[cycle],
      });
      await Linking.openURL(url);
    },
    onError: (error: any) => {
      Alert.alert('Upgrade failed', error?.message || 'Could not start checkout.');
    },
  });

  return (
    <SettingsScreenContainer>
      {!billingEnabled ? (
        <SettingsCard>
          <SettingsSectionTitle>Billing Unavailable</SettingsSectionTitle>
          <SettingsDescription>
            Billing requires a signed-in account session. Auth bypass mode does not include billing
            credentials.
          </SettingsDescription>
          <SettingsButton
            variant="secondary"
            label="Open Billing on Web"
            onPress={() => {
              void openPricingOnWeb();
            }}
          />
        </SettingsCard>
      ) : customerQuery.isError ? (
        <SettingsCard>
          <SettingsSectionTitle>Billing Sync Failed</SettingsSectionTitle>
          <SettingsDescription>
            {(customerQuery.error as Error | undefined)?.message ??
              'Could not load billing details from the server.'}
          </SettingsDescription>
          <SettingsButton label="Retry Billing Sync" onPress={() => customerQuery.refetch()} />
          <SettingsButton
            variant="secondary"
            label="Open Billing on Web"
            onPress={() => {
              void openPricingOnWeb();
            }}
          />
        </SettingsCard>
      ) : customerQuery.isLoading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator color={colors.foreground} />
        </View>
      ) : (
        <>
          <SettingsCard>
            <SettingsSectionTitle>Plan</SettingsSectionTitle>
            <SettingsDescription>
              Manage your subscription and usage limits from Autumn billing.
            </SettingsDescription>
            <Text style={[styles.planStatus, { color: colors.foreground }]}>
              {isPro ? 'Pro plan active' : 'Free plan'}
            </Text>
            {featureRows.length > 0 ? (
              <View style={[styles.featureList, { borderColor: ui.borderSubtle }]}>
                {featureRows.map((feature, index) => (
                  <View
                    key={feature.id}
                    style={[
                      styles.featureRow,
                      index < featureRows.length - 1 && {
                        borderBottomWidth: StyleSheet.hairlineWidth,
                        borderBottomColor: ui.borderSubtle,
                      },
                    ]}
                  >
                    <Text style={[styles.featureLabel, { color: colors.foreground }]}>
                      {feature.label}
                    </Text>
                    <Text style={[styles.featureValue, { color: colors.mutedForeground }]}>
                      {feature.value}
                    </Text>
                  </View>
                ))}
              </View>
            ) : (
              <Text style={[styles.emptyFeatures, { color: colors.mutedForeground }]}>
                Usage details are not available yet for this account.
              </Text>
            )}
          </SettingsCard>

          <SettingsCard>
            <SettingsSectionTitle>Upgrade</SettingsSectionTitle>
            <SettingsDescription>
              Start checkout for the selected billing cycle.
            </SettingsDescription>
            <SettingsOptionGroup<BillingCycle>
              value={cycle}
              onSelect={setCycle}
              options={[
                { label: 'Monthly', value: 'monthly' },
                { label: 'Annual', value: 'annual' },
              ]}
            />
            <SettingsButton
              label={upgradeMutation.isPending ? 'Opening Checkout...' : 'Upgrade to Pro'}
              onPress={() => upgradeMutation.mutate()}
              disabled={upgradeMutation.isPending || billingPortalMutation.isPending}
            />
          </SettingsCard>

          <SettingsCard>
            <SettingsSectionTitle>Billing Portal</SettingsSectionTitle>
            <SettingsDescription>
              Manage payment methods, invoices, and subscription status.
            </SettingsDescription>
            <SettingsButton
              variant="secondary"
              label={
                billingPortalMutation.isPending ? 'Opening Billing Portal...' : 'Manage Billing'
              }
              onPress={() => billingPortalMutation.mutate()}
              disabled={upgradeMutation.isPending || billingPortalMutation.isPending}
            />
          </SettingsCard>
        </>
      )}
    </SettingsScreenContainer>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    minHeight: 180,
    alignItems: 'center',
    justifyContent: 'center',
  },
  planStatus: {
    fontSize: typography.size.md,
    fontWeight: '600',
  },
  featureList: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    overflow: 'hidden',
  },
  featureRow: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  featureLabel: {
    fontSize: typography.size.sm,
    fontWeight: '500',
    textTransform: 'capitalize',
  },
  featureValue: {
    fontSize: typography.size.sm,
  },
  emptyFeatures: {
    fontSize: typography.size.sm,
  },
});
