/**
 * Native PostHog client singleton for analytics parity with web.
 */
import PostHog from 'posthog-react-native';

type AnalyticsProperties = Record<string, any>;

let posthogClient: PostHog | null = null;

export function initPostHog(config: { apiKey?: string; host?: string }) {
  if (!config.apiKey || posthogClient) {
    return;
  }

  posthogClient = new PostHog(config.apiKey, {
    host: config.host || 'https://us.i.posthog.com',
    captureAppLifecycleEvents: true,
  });
}

export function captureEvent(event: string, properties?: AnalyticsProperties) {
  if (!posthogClient) return;
  posthogClient.capture(event, properties as any);
}

export function identifyPostHog(distinctId: string, properties?: AnalyticsProperties) {
  if (!posthogClient || !distinctId) return;
  posthogClient.identify(distinctId, properties as any);
}

export function captureScreen(screenName: string, properties?: AnalyticsProperties) {
  if (!posthogClient) return;
  void posthogClient.screen(screenName, properties as any);
}

export function flushPostHog() {
  if (!posthogClient) return Promise.resolve();
  return posthogClient.flush();
}
