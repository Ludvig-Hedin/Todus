/* Todus web push service worker.
 *
 * Receives encrypted push payloads (sent by apps/server/src/lib/push.ts) and
 * shows a notification. On click, focuses an existing Todus tab (navigating it
 * to the payload URL) or opens a new one. Kept dependency-free and tiny so it
 * stays cheap to install/update.
 */

self.addEventListener('install', () => {
  // Activate this SW immediately instead of waiting for existing tabs to close.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Take control of already-open clients so push works without a reload.
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch {
    // Non-JSON payloads fall back to plain text in the body.
    payload = { title: 'Todus', body: event.data ? event.data.text() : '' };
  }

  const title = payload.title || 'Todus';
  const options = {
    body: payload.body || '',
    icon: payload.icon || '/icons-pwa/icon-192.png',
    badge: payload.badge || '/icons-pwa/icon-192.png',
    // tag collapses repeat notifications; renotify re-alerts on update.
    tag: payload.tag || 'todus',
    renotify: Boolean(payload.tag),
    data: { url: payload.url || '/mail' },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || '/mail';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        // Reuse an existing Todus tab when one is open.
        if ('focus' in client) {
          client.focus();
          if ('navigate' in client && targetUrl) {
            return client.navigate(targetUrl).catch(() => undefined);
          }
          return undefined;
        }
      }
      // No open tab — open a new one at the target URL.
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
      return undefined;
    }),
  );
});
