import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsSwitchRow,
} from '../../../src/features/settings/SettingsUI';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useRouter } from 'expo-router';
import { Alert } from 'react-native';
import { useEffect, useState } from 'react';

const TWO_FACTOR_KEY = 'settings.security.twoFactorAuth';
const LOGIN_NOTIFICATIONS_KEY = 'settings.security.loginNotifications';

export default function SecuritySettings() {
  const router = useRouter();
  const [twoFactorAuth, setTwoFactorAuth] = useState(false);
  const [loginNotifications, setLoginNotifications] = useState(true);
  const [isDirty, setIsDirty] = useState(false);

  useEffect(() => {
    void (async () => {
      try {
        const [twoFactor, login] = await Promise.all([
          AsyncStorage.getItem(TWO_FACTOR_KEY),
          AsyncStorage.getItem(LOGIN_NOTIFICATIONS_KEY),
        ]);
        if (twoFactor === 'true' || twoFactor === 'false') {
          setTwoFactorAuth(twoFactor === 'true');
        }
        if (login === 'true' || login === 'false') {
          setLoginNotifications(login === 'true');
        }
        setIsDirty(false);
      } catch (error) {
        console.error('[security] failed to load preferences', error);
      }
    })();
  }, []);

  const saveChanges = async () => {
    try {
      await Promise.all([
        AsyncStorage.setItem(TWO_FACTOR_KEY, String(twoFactorAuth)),
        AsyncStorage.setItem(LOGIN_NOTIFICATIONS_KEY, String(loginNotifications)),
      ]);
      setIsDirty(false);
      Alert.alert('Saved', 'Security preferences were saved locally on this device.');
    } catch (error) {
      console.error('[security] failed to save preferences', error);
      Alert.alert('Save failed', 'Could not save security preferences.');
    }
  };

  return (
    <SettingsScreenContainer>
      <SettingsCard>
        <SettingsSectionTitle>Protection</SettingsSectionTitle>
        <SettingsDescription>
          Configure account protection and login activity notifications.
        </SettingsDescription>
        <SettingsSwitchRow
          label="Two-Factor Authentication"
          description="Require an extra verification step at sign in."
          value={twoFactorAuth}
          onValueChange={(value) => {
            setTwoFactorAuth(value);
            setIsDirty(true);
          }}
        />
        <SettingsSwitchRow
          label="Login Notifications"
          description="Receive alerts for new sign-ins."
          value={loginNotifications}
          onValueChange={(value) => {
            setLoginNotifications(value);
            setIsDirty(true);
          }}
        />
      </SettingsCard>

      <SettingsButton
        label="Danger Zone"
        onPress={() => router.push('/(app)/settings/danger-zone')}
        variant="destructive"
      />
      <SettingsButton label="Save Changes" onPress={saveChanges} disabled={!isDirty} />
    </SettingsScreenContainer>
  );
}
