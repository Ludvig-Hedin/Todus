import { useAutumn, useCustomer } from 'autumn-js/react';
import { signOut } from '@/lib/auth-client';
import { isProCustomer } from '@/lib/utils';
import { useEffect, useMemo } from 'react';

type FeatureState = {
  total: number;
  remaining: number;
  unlimited: boolean;
  enabled: boolean;
  usage: number;
  nextResetAt: number | null;
  interval: string;
  included_usage: number;
};

type Features = {
  chatMessages: FeatureState;
  connections: FeatureState;
  brainActivity: FeatureState;
  aiUsage: FeatureState;
};

const emptyFeatureState = (): FeatureState => ({
  total: 0,
  remaining: 0,
  unlimited: false,
  enabled: false,
  usage: 0,
  nextResetAt: null,
  interval: '',
  included_usage: 0,
});

const DEFAULT_FEATURES: Features = {
  chatMessages: emptyFeatureState(),
  connections: emptyFeatureState(),
  brainActivity: emptyFeatureState(),
  aiUsage: emptyFeatureState(),
};

const FEATURE_IDS = {
  CHAT: 'chat-messages',
  CONNECTIONS: 'connections',
  BRAIN: 'brain-activity',
  AI_USAGE: 'ai_usage',
} as const;

export const useBilling = () => {
  const { customer, refetch, isLoading, error } = useCustomer();
  const { attach, track, openBillingPortal } = useAutumn();

  useEffect(() => {
    if (error) signOut();
  }, [error]);

  const { isPro, ...customerFeatures } = useMemo(() => {
    const isPro = customer ? isProCustomer(customer) : false;

    if (!customer?.features) return { isPro, ...DEFAULT_FEATURES };

    const features = { ...DEFAULT_FEATURES };

    if (customer.features[FEATURE_IDS.CHAT]) {
      const feature = customer.features[FEATURE_IDS.CHAT];
      features.chatMessages = {
        total: feature.included_usage || 0,
        remaining: feature.balance || 0,
        unlimited: feature.unlimited ?? false,
        enabled: (feature.unlimited ?? false) || Number(feature.balance) > 0,
        usage: feature.usage || 0,
        nextResetAt: feature.next_reset_at ?? null,
        interval: feature.interval || '',
        included_usage: feature.included_usage || 0,
      };
    }

    if (customer.features[FEATURE_IDS.CONNECTIONS]) {
      const feature = customer.features[FEATURE_IDS.CONNECTIONS];
      features.connections = {
        total: feature.included_usage || 0,
        remaining: feature.balance || 0,
        unlimited: feature.unlimited ?? false,
        enabled: (feature.unlimited ?? false) || Number(feature.balance) > 0,
        usage: feature.usage || 0,
        nextResetAt: feature.next_reset_at ?? null,
        interval: feature.interval || '',
        included_usage: feature.included_usage || 0,
      };
    }

    if (customer.features[FEATURE_IDS.BRAIN]) {
      const feature = customer.features[FEATURE_IDS.BRAIN];
      features.brainActivity = {
        total: feature.included_usage || 0,
        remaining: feature.balance || 0,
        unlimited: feature.unlimited ?? false,
        enabled: (feature.unlimited ?? false) || Number(feature.balance) > 0,
        usage: feature.usage || 0,
        nextResetAt: feature.next_reset_at ?? null,
        interval: feature.interval || '',
        included_usage: feature.included_usage || 0,
      };
    }

    if (customer.features[FEATURE_IDS.AI_USAGE]) {
      const feature = customer.features[FEATURE_IDS.AI_USAGE];
      features.aiUsage = {
        total: feature.included_usage || 0,
        remaining: feature.balance || 0,
        unlimited: feature.unlimited ?? false,
        enabled: (feature.unlimited ?? false) || Number(feature.balance) > 0,
        usage: feature.usage || 0,
        nextResetAt: feature.next_reset_at ?? null,
        interval: feature.interval || '',
        included_usage: feature.included_usage || 0,
      };
    }

    return { isPro, ...features };
  }, [customer]);

  return {
    isLoading,
    customer,
    refetch,
    attach,
    track,
    openBillingPortal,
    isPro,
    ...customerFeatures,
  };
};
