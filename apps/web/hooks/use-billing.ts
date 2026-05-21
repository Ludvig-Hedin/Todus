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

  // Stabilize the effect deps on the error's PRIMITIVE shape — `error` is a
  // fresh object reference on every render while an error persists, so the
  // old `[error]` dep would re-fire the side effects (and possibly repeat
  // signOut) every render. Tracking only status/code/message stays stable
  // across re-renders for the same error.
  const errorStatus = (error as { status?: number } | null | undefined)?.status;
  const errorCode = (error as { code?: string } | null | undefined)?.code;
  const errorMessage = error instanceof Error ? error.message : undefined;
  useEffect(() => {
    if (!error) return;
    // Only sign out on explicit auth failures. Transient billing errors
    // (network blip, Autumn 5xx, CORS hiccup) must NOT force a logout —
    // useBilling is mounted app-wide via NavUser so any error here
    // would log every active user out.
    if (errorStatus === 401 || errorStatus === 403 || errorCode === 'UNAUTHENTICATED') {
      signOut();
    } else {
      console.error('Billing error (ignored, not auth-related):', error);
    }
    // We intentionally depend on the stable primitives, not the object itself.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [errorStatus, errorCode, errorMessage]);

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
