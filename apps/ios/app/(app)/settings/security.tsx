import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsSwitchRow,
} from '../../../src/features/settings/SettingsUI';
import { useRouter } from 'expo-router';
import { Alert } from 'react-native';
import { useState } from 'react';

export default function SecuritySettings() {
  const router = useRouter();
  const [twoFactorAuth, setTwoFactorAuth] = useState(false);
  const [loginNotifications, setLoginNotifications] = useState(true);
  const [isDirty, setIsDirty] = useState(false);

  const saveChanges = () => {
    // Backend endpoints for these preferences are not yet exposed in current API.
    setIsDirty(false);
    Alert.alert('Saved', 'Security preferences were saved locally on this device.');
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
