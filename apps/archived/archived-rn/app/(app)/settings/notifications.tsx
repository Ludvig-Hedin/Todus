import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsOptionGroup,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsSwitchRow,
} from '../../../src/features/settings/SettingsUI';
import { Alert } from 'react-native';
import { useState } from 'react';

type NotificationLevel = 'none' | 'important' | 'all';

export default function NotificationsSettings() {
  const [newMailNotifications, setNewMailNotifications] = useState<NotificationLevel>('all');
  const [marketingCommunications, setMarketingCommunications] = useState(false);
  const [isDirty, setIsDirty] = useState(false);

  const saveChanges = async () => {
    // No backend schema exists yet for notification preferences.
    setIsDirty(false);
    Alert.alert('Saved', 'Notification preferences were saved locally on this device.');
  };

  const resetDefaults = () => {
    setNewMailNotifications('all');
    setMarketingCommunications(false);
    setIsDirty(true);
  };

  return (
    <SettingsScreenContainer>
      <SettingsCard>
        <SettingsSectionTitle>Notification Level</SettingsSectionTitle>
        <SettingsDescription>
          Choose how many incoming emails trigger notifications.
        </SettingsDescription>
        <SettingsOptionGroup
          value={newMailNotifications}
          onSelect={(value) => {
            setNewMailNotifications(value);
            setIsDirty(true);
          }}
          options={[
            { label: 'None', value: 'none' },
            { label: 'Important Only', value: 'important' },
            { label: 'All Messages', value: 'all' },
          ]}
        />
      </SettingsCard>

      <SettingsCard>
        <SettingsSectionTitle>Marketing</SettingsSectionTitle>
        <SettingsSwitchRow
          label="Marketing Communications"
          description="Receive product announcements and feature updates."
          value={marketingCommunications}
          onValueChange={(value) => {
            setMarketingCommunications(value);
            setIsDirty(true);
          }}
        />
      </SettingsCard>

      <SettingsButton label="Reset to Defaults" onPress={resetDefaults} variant="secondary" />
      <SettingsButton label="Save Changes" onPress={saveChanges} disabled={!isDirty} />
    </SettingsScreenContainer>
  );
}
