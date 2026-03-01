import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsSwitchRow,
  SettingsTextInput,
} from '../../../src/features/settings/SettingsUI';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useEffect, useMemo, useState } from 'react';

export default function PrivacySettings() {
  const { colors } = useTheme();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery(trpc.settings.get.queryOptions());
  const [externalImages, setExternalImages] = useState(true);
  const [trustedSenders, setTrustedSenders] = useState<string[]>([]);
  const [newSender, setNewSender] = useState('');
  const [isDirty, setIsDirty] = useState(false);

  const saveMutation = useMutation({
    ...trpc.settings.save.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      setIsDirty(false);
    },
  });

  useEffect(() => {
    const settings = settingsQuery.data?.settings;
    if (!settings) return;
    setExternalImages(settings.externalImages ?? true);
    setTrustedSenders(settings.trustedSenders ?? []);
    setIsDirty(false);
  }, [settingsQuery.data?.settings]);

  const normalizedNewSender = useMemo(() => newSender.trim().toLowerCase(), [newSender]);

  const addTrustedSender = () => {
    if (!normalizedNewSender) return;
    if (trustedSenders.includes(normalizedNewSender)) return;
    setTrustedSenders((current) => [...current, normalizedNewSender]);
    setNewSender('');
    setIsDirty(true);
  };

  const removeTrustedSender = (email: string) => {
    setTrustedSenders((current) => current.filter((sender) => sender !== email));
    setIsDirty(true);
  };

  const saveChanges = async () => {
    try {
      await saveMutation.mutateAsync({
        externalImages,
        trustedSenders,
      });
      Alert.alert('Saved', 'Privacy settings were updated.');
    } catch (error: any) {
      Alert.alert('Save failed', error?.message || 'Could not save privacy settings.');
    }
  };

  if (settingsQuery.isLoading) {
    return (
      <View style={[styles.loading, { backgroundColor: colors.background }]}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  return (
    <SettingsScreenContainer>
      <SettingsCard>
        <SettingsSectionTitle>External Images</SettingsSectionTitle>
        <SettingsSwitchRow
          label="Load External Images"
          description="Automatically load remote images embedded in emails."
          value={externalImages}
          onValueChange={(value) => {
            setExternalImages(value);
            setIsDirty(true);
          }}
        />
      </SettingsCard>

      <SettingsCard>
        <SettingsSectionTitle>Trusted Senders</SettingsSectionTitle>
        <SettingsDescription>
          When external images are disabled, trusted senders can still load images by default.
        </SettingsDescription>
        <View style={styles.addSenderRow}>
          <View style={styles.addSenderInput}>
            <SettingsTextInput
              value={newSender}
              onChangeText={setNewSender}
              placeholder="name@example.com"
            />
          </View>
          <View style={styles.addSenderButton}>
            <SettingsButton label="Add" onPress={addTrustedSender} variant="secondary" />
          </View>
        </View>
        {trustedSenders.length === 0 ? (
          <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
            No trusted senders configured.
          </Text>
        ) : (
          trustedSenders.map((sender) => (
            <View key={sender} style={[styles.senderRow, { borderColor: colors.border }]}>
              <Text style={[styles.senderText, { color: colors.foreground }]}>{sender}</Text>
              <Pressable onPress={() => removeTrustedSender(sender)}>
                <Text style={{ color: colors.destructive, fontWeight: '600' }}>Remove</Text>
              </Pressable>
            </View>
          ))
        )}
      </SettingsCard>

      <SettingsButton
        label={saveMutation.isPending ? 'Saving...' : 'Save Changes'}
        onPress={saveChanges}
        disabled={saveMutation.isPending || !isDirty}
      />
    </SettingsScreenContainer>
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addSenderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  addSenderInput: {
    flex: 1,
  },
  addSenderButton: {
    width: 90,
  },
  emptyText: {
    fontSize: 13,
  },
  senderRow: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  senderText: {
    fontSize: 14,
    flex: 1,
  },
});
