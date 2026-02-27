import AsyncStorage from '@react-native-async-storage/async-storage';
import type { NativeAuthSession } from '@zero/shared';

const SESSION_KEY = 'zero:session:v1';
const THEME_MODE_KEY = 'zero:theme:mode';
const LAST_VISITED_PATH_KEY = 'zero:last-visited-path';

type ThemeMode = 'light' | 'dark' | 'system';

async function readJson<T>(key: string): Promise<T | null> {
  const rawValue = await AsyncStorage.getItem(key);
  if (!rawValue) return null;
  try {
    return JSON.parse(rawValue) as T;
  } catch {
    return null;
  }
}

class SecureStorageAdapter {
  async getSession(): Promise<NativeAuthSession | null> {
    return readJson<NativeAuthSession>(SESSION_KEY);
  }

  async setSession(session: NativeAuthSession): Promise<void> {
    await AsyncStorage.setItem(SESSION_KEY, JSON.stringify(session));
  }

  async clearSession(): Promise<void> {
    await AsyncStorage.removeItem(SESSION_KEY);
  }

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

  async getLastVisitedPath(): Promise<string | null> {
    return AsyncStorage.getItem(LAST_VISITED_PATH_KEY);
  }

  async setLastVisitedPath(path: string): Promise<void> {
    await AsyncStorage.setItem(LAST_VISITED_PATH_KEY, path);
  }
}

export const secureStorage = new SecureStorageAdapter();
