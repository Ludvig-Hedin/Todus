import { app, BrowserWindow, shell } from 'electron';

const WEB_BASE_URL =
  process.env.EXPO_PUBLIC_WEB_URL ?? 'https://zero-production.ludvighedin15.workers.dev';
const BACKEND_URL =
  process.env.EXPO_PUBLIC_BACKEND_URL ??
  'https://zero-server-v1-production.ludvighedin15.workers.dev';
const APP_ENTRY_URL = process.env.EXPO_PUBLIC_APP_ENTRY_URL ?? `${WEB_BASE_URL}/mail/inbox`;

const allowedHosts = new Set([
  new URL(WEB_BASE_URL).host,
  new URL(BACKEND_URL).host,
  'accounts.google.com',
  'oauth2.googleapis.com',
]);

const isAllowedUrl = (rawUrl) => {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return false;
    return allowedHosts.has(parsed.host);
  } catch {
    return false;
  }
};

const createWindow = () => {
  const win = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 1000,
    minHeight: 700,
    title: 'Zero Mail',
    backgroundColor: '#0b0f14',
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
    },
  });

  win.webContents.setWindowOpenHandler(({ url }) => {
    if (isAllowedUrl(url)) {
      win.loadURL(url);
      return { action: 'deny' };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });

  win.webContents.on('will-navigate', (event, url) => {
    if (isAllowedUrl(url)) return;
    event.preventDefault();
    shell.openExternal(url);
  });

  win.loadURL(APP_ENTRY_URL);
};

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
