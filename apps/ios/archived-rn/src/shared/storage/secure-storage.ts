/**
 * Secure storage adapter using expo-secure-store for sensitive data (session tokens)
 * and AsyncStorage for non-sensitive preferences (theme, last path).
 */
import * as SecureStore from 'expo-secure-store';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type { NativeAuthSession } from '@zero/shared';

// expo-secure-store accepts only [A-Za-z0-9._-] in keys.
const SESSION_KEY = 'zero.session.v1';
const THEME_MODE_KEY = 'zero:theme:mode';
const LAST_VISITED_PATH_KEY = 'zero:last-visited-path';

type ThemeMode = 'light' | 'dark' | 'system';

class SecureStorageAdapter {
  /** Session token stored in Keychain (encrypted) */
  async getSession(): Promise<NativeAuthSession | null> {
    try {
      const rawValue = await SecureStore.getItemAsync(SESSION_KEY);
      if (!rawValue) return null;
      return JSON.parse(rawValue) as NativeAuthSession;
    } catch {
      return null;
    }
  }

  async setSession(session: NativeAuthSession): Promise<void> {
    try {
      await SecureStore.setItemAsync(SESSION_KEY, JSON.stringify(session));
    } catch {
      // No-op: callers should continue gracefully if secure storage is unavailable.
    }
  }

  async clearSession(): Promise<void> {
    try {
      await SecureStore.deleteItemAsync(SESSION_KEY);
    } catch {
      // No-op: clearing a missing/invalid key should not block logout flow.
    }
  }

  /** Theme mode stored in AsyncStorage (non-sensitive) */
  async getThemeMode(): Promise<ThemeMode> {
    const value = await AsyncStorage.getItem(THEME_MODE_KEY);
    if (value === 'light' || value === 'dark' || value === 'system') {
      return value;
    }
    return 'system';
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    await AsyncStorage.setItem(THEME_MODE_KEY, mode);
  }

  /** Last visited path stored in AsyncStorage (non-sensitive) */
  async getLastVisitedPath(): Promise<string | null> {
    return AsyncStorage.getItem(LAST_VISITED_PATH_KEY);
  }

  async setLastVisitedPath(path: string): Promise<void> {
    await AsyncStorage.setItem(LAST_VISITED_PATH_KEY, path);
  }
}

export const secureStorage = new SecureStorageAdapter();
