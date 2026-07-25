import {
  BaseSubscriptionFactory,
  type SubscriptionData,
  type UnsubscriptionData,
} from './base-subscription.factory';
import { EProviders } from '../../types';

export class OutlookSubscriptionFactory extends BaseSubscriptionFactory {
  readonly providerId = EProviders.microsoft;

  public async subscribe(_: { body: SubscriptionData }): Promise<Response> {
    // TODO (backlog 0462): Implement Outlook subscription logic
    // This will handle Microsoft Graph API subscriptions for Outlook
    console.warn('[Outlook] Subscription not implemented yet');
    return new Response('Not Implemented', { status: 501 });
  }

  public async unsubscribe(_: { body: UnsubscriptionData }): Promise<Response> {
    // TODO (backlog 0462): Implement Outlook unsubscription logic
    console.warn('[Outlook] Unsubscription not implemented yet');
    return new Response('Not Implemented', { status: 501 });
  }

  public async verifyToken(_: string): Promise<boolean> {
    // TODO (backlog 0462): Implement Microsoft Graph token verification
    console.warn('[Outlook] Token verification not implemented yet');
    return false;
  }
}
