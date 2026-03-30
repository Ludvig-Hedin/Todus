import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsOptionGroup,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsSwitchRow,
} from '../../../src/features/settings/SettingsUI';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Alert } from 'react-native';
import { useEffect, useState } from 'react';

type NotificationLevel = 'none' | 'important' | 'all';
const NOTIFICATION_LEVEL_KEY = 'settings.notifications.level';
const MARKETING_KEY = 'settings.notifications.marketing';

export default function NotificationsSettings() {
  const [newMailNotifications, setNewMailNotifications] = useState<NotificationLevel>('all');
  const [marketingCommunications, setMarketingCommunications] = useState(false);
  const [isDirty, setIsDirty] = useState(false);

  useEffect(() => {
    void (async () => {
      try {
        const [level, marketing] = await Promise.all([
          AsyncStorage.getItem(NOTIFICATION_LEVEL_KEY),
          AsyncStorage.getItem(MARKETING_KEY),
        ]);
        if (level === 'none' || level === 'important' || level === 'all') {
          setNewMailNotifications(level);
        }
        if (marketing === 'true' || marketing === 'false') {
          setMarketingCommunications(marketing === 'true');
        }
        setIsDirty(false);
      } catch (error) {
        console.error('[notifications] failed to load preferences', error);
      }
    })();
  }, []);

  const saveChanges = async () => {
    try {
      await Promise.all([
        AsyncStorage.setItem(NOTIFICATION_LEVEL_KEY, newMailNotifications),
        AsyncStorage.setItem(MARKETING_KEY, String(marketingCommunications)),
      ]);
      setIsDirty(false);
      Alert.alert('Saved', 'Notification preferences were saved locally on this device.');
    } catch (error) {
      console.error('[notifications] failed to save preferences', error);
      Alert.alert('Save failed', 'Could not save notification preferences.');
    }
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
