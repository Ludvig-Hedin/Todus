'use client';

import { useCallback, useEffect, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { Section, RowList, ToggleRow } from '@/components/settings/primitives';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

/** Decode a base64url VAPID public key into the Uint8Array PushManager wants. */
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const output = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) output[i] = raw.charCodeAt(i);
  return output;
}

function pushSupported() {
  return (
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  );
}

export function PushNotificationsSection() {
  const trpc = useTRPC();
  const [supported, setSupported] = useState(false);
  const [subscribed, setSubscribed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [permissionDenied, setPermissionDenied] = useState(false);

  const { data: keyData } = useQuery(trpc.push.getPublicKey.queryOptions());
  const subscribeMutation = useMutation(trpc.push.subscribe.mutationOptions());
  const unsubscribeMutation = useMutation(trpc.push.unsubscribe.mutationOptions());
  const sendTestMutation = useMutation(trpc.push.sendTest.mutationOptions());

  // Detect support + current subscription/permission on mount.
  useEffect(() => {
    if (!pushSupported()) return;
    setSupported(true);
    setPermissionDenied(Notification.permission === 'denied');
    navigator.serviceWorker.ready
      .then((reg) => reg.pushManager.getSubscription())
      .then((sub) => setSubscribed(!!sub))
      .catch(() => setSubscribed(false));
  }, []);

  const enable = useCallback(async () => {
    if (!keyData?.publicKey) {
      toast.error('Push is not configured on the server yet.');
      return;
    }
    setBusy(true);
    try {
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        setPermissionDenied(permission === 'denied');
        toast.error('Notification permission was not granted.');
        return;
      }
      setPermissionDenied(false);

      const reg = await navigator.serviceWorker.ready;
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          // Cast: PushManager wants BufferSource; TS widens Uint8Array's buffer
          // to ArrayBufferLike (incl. SharedArrayBuffer) which it won't accept.
          applicationServerKey: urlBase64ToUint8Array(keyData.publicKey) as BufferSource,
        });
      }

      const json = sub.toJSON();
      if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) {
        throw new Error('Subscription missing endpoint or keys');
      }

      await subscribeMutation.mutateAsync({
        endpoint: json.endpoint,
        keys: { p256dh: json.keys.p256dh, auth: json.keys.auth },
        expirationTime:
          typeof sub.expirationTime === 'number' ? sub.expirationTime : null,
      });

      setSubscribed(true);
      toast.success('Push notifications enabled on this device.');
    } catch (error) {
      console.error('[push] enable failed', error);
      toast.error('Could not enable push notifications.');
    } finally {
      setBusy(false);
    }
  }, [keyData?.publicKey, subscribeMutation]);

  const disable = useCallback(async () => {
    setBusy(true);
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) {
        const endpoint = sub.endpoint;
        await sub.unsubscribe().catch(() => undefined);
        await unsubscribeMutation.mutateAsync({ endpoint }).catch(() => undefined);
      }
      setSubscribed(false);
      toast.success('Push notifications disabled on this device.');
    } catch (error) {
      console.error('[push] disable failed', error);
      toast.error('Could not disable push notifications.');
    } finally {
      setBusy(false);
    }
  }, [unsubscribeMutation]);

  const onToggle = useCallback(
    (next: boolean) => {
      if (busy) return;
      if (next) void enable();
      else void disable();
    },
    [busy, enable, disable],
  );

  const sendTest = useCallback(async () => {
    try {
      const result = await sendTestMutation.mutateAsync();
      if (result.skipped) {
        toast.error('Push is not configured on the server (no VAPID keys).');
      } else if (result.sent > 0) {
        toast.success(`Test notification sent (${result.sent} device${result.sent > 1 ? 's' : ''}).`);
      } else {
        toast.error('No active subscriptions to send to. Enable push first.');
      }
    } catch {
      toast.error('Failed to send test notification.');
    }
  }, [sendTestMutation]);

  if (!supported) {
    return (
      <Section
        title="Push notifications"
        description="Get task and event reminders in this browser, even when Todus isn't open."
      >
        <p className="text-muted-foreground text-[13px]">
          This browser doesn't support web push notifications.
        </p>
      </Section>
    );
  }

  return (
    <Section
      title="Push notifications"
      description="Get task and event reminders in this browser, even when Todus isn't open."
    >
      <RowList>
        <ToggleRow
          label="Enable on this device"
          description={
            permissionDenied
              ? 'Blocked in your browser settings. Allow notifications for this site, then try again.'
              : 'Allow this browser to receive push notifications from Todus.'
          }
          checked={subscribed}
          onChange={onToggle}
        />
      </RowList>
      {subscribed && (
        <Button
          variant="outline"
          size="sm"
          className="mt-3"
          disabled={sendTestMutation.isPending}
          onClick={() => void sendTest()}
        >
          {sendTestMutation.isPending ? 'Sending…' : 'Send test notification'}
        </Button>
      )}
    </Section>
  );
}
