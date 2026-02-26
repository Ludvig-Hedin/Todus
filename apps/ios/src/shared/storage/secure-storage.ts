/**
 * Secure storage adapter using expo-secure-store for sensitive data (session tokens)
 * and AsyncStorage for non-sensitive preferences (theme, last path).
 */
import * as SecureStore from 'expo-secure-store';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type { NativeAuthSession } from '@zero/shared';

const SESSION_KEY = 'zero:session:v1';
const THEME_MODE_KEY = 'zero:theme:mode';
const LAST_VISITED_PATH_KEY = 'zero:last-visited-path';

type ThemeMode = 'light' | 'dark' | 'system';

class SecureStorageAdapter {
  /** Session token stored in Keychain (encrypted) */
  async getSession(): Promise<NativeAuthSession | null> {
    const rawValue = await SecureStore.getItemAsync(SESSION_KEY);
    if (!rawValue) return null;
    try {
      return JSON.parse(rawValue) as NativeAuthSession;
    } catch {
      return null;
    }
  }

  async setSession(session: NativeAuthSession): Promise<void> {
    await SecureStore.setItemAsync(SESSION_KEY, JSON.stringify(session));
  }

  async clearSession(): Promise<void> {
    await SecureStore.deleteItemAsync(SESSION_KEY);
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
