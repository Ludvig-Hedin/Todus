import AsyncStorage from '@react-native-async-storage/async-storage';
import { secureStorage } from './secure-storage';

describe('secureStorage', () => {
  beforeEach(async () => {
    await AsyncStorage.clear();
  });

  it('stores and clears session state', async () => {
    await secureStorage.setSession({
      mode: 'bearer',
      token: 'token-123',
      createdAt: Date.now(),
      expiresAt: null,
    });

    await expect(secureStorage.getSession()).resolves.toEqual(
      expect.objectContaining({
        mode: 'bearer',
        token: 'token-123',
      }),
    );

    await secureStorage.clearSession();
    await expect(secureStorage.getSession()).resolves.toBeNull();
  });

  it('defaults to system theme when not set', async () => {
    await expect(secureStorage.getThemeMode()).resolves.toBe('system');
  });

  it('stores last visited path', async () => {
    await secureStorage.setLastVisitedPath('/mail/inbox');
    await expect(secureStorage.getLastVisitedPath()).resolves.toBe('/mail/inbox');
  });
});
