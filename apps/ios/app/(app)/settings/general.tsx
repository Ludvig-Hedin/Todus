/**
 * General settings — language/timezone/default alias and core mail behavior toggles.
 */
import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsFieldLabel,
  SettingsOptionGroup,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsSwitchRow,
  SettingsTextInput,
} from '../../../src/features/settings/SettingsUI';
import { ActivityIndicator, Alert, StyleSheet, Text, View } from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useEffect, useMemo, useState } from 'react';

type GeneralFormState = {
  language: string;
  timezone: string;
  defaultEmailAlias: string;
  todusSignature: boolean;
  autoRead: boolean;
  undoSendEnabled: boolean;
  animations: boolean;
};

const DEFAULT_FORM_STATE: GeneralFormState = {
  language: 'en',
  timezone: 'UTC',
  defaultEmailAlias: '',
  todusSignature: true,
  autoRead: true,
  undoSendEnabled: false,
  animations: false,
};

export default function GeneralSettings() {
  const { colors } = useTheme();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [form, setForm] = useState<GeneralFormState>(DEFAULT_FORM_STATE);
  const [isDirty, setIsDirty] = useState(false);

  const settingsQuery = useQuery(trpc.settings.get.queryOptions());
  const connectionsQuery = useQuery(trpc.connections.list.queryOptions());

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
    setForm({
      language: settings.language || 'en',
      timezone: settings.timezone || 'UTC',
      defaultEmailAlias: settings.defaultEmailAlias || '',
      todusSignature: settings.todusSignature ?? true,
      autoRead: settings.autoRead ?? true,
      undoSendEnabled: settings.undoSendEnabled ?? false,
      animations: settings.animations ?? false,
    });
    setIsDirty(false);
  }, [settingsQuery.data?.settings]);

  const aliasOptions = useMemo(() => {
    const connections = connectionsQuery.data?.connections ?? [];
    return connections
      .map((connection) => connection.email)
      .filter((email): email is string => Boolean(email));
  }, [connectionsQuery.data?.connections]);

  const updateForm = (next: Partial<GeneralFormState>) => {
    setForm((current) => ({ ...current, ...next }));
    setIsDirty(true);
  };

  const saveChanges = async () => {
    try {
      await saveMutation.mutateAsync({
        language: form.language,
        timezone: form.timezone,
        defaultEmailAlias: form.defaultEmailAlias || '',
        todusSignature: form.todusSignature,
        autoRead: form.autoRead,
        undoSendEnabled: form.undoSendEnabled,
        animations: form.animations,
      });
      Alert.alert('Saved', 'General settings were updated.');
    } catch (error: any) {
      Alert.alert('Save failed', error?.message || 'Could not save general settings.');
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
        <SettingsSectionTitle>Locale</SettingsSectionTitle>
        <SettingsDescription>
          Language and timezone used for date/time rendering.
        </SettingsDescription>

        <SettingsFieldLabel>Language</SettingsFieldLabel>
        <SettingsOptionGroup
          value={form.language}
          onSelect={(language) => updateForm({ language })}
          options={[
            { label: 'English', value: 'en' },
            { label: 'Swedish', value: 'sv' },
          ]}
        />

        <SettingsFieldLabel>Timezone</SettingsFieldLabel>
        <SettingsTextInput
          value={form.timezone}
          onChangeText={(timezone) => updateForm({ timezone })}
          placeholder="UTC"
        />
      </SettingsCard>

      <SettingsCard>
        <SettingsSectionTitle>Composing</SettingsSectionTitle>
        <SettingsDescription>
          Default sender identity used in compose and reply flows.
        </SettingsDescription>
        <SettingsFieldLabel>Default Email Alias</SettingsFieldLabel>
        <SettingsOptionGroup
          value={form.defaultEmailAlias || 'none'}
          onSelect={(value) => updateForm({ defaultEmailAlias: value === 'none' ? '' : value })}
          options={[
            { label: 'None', value: 'none' },
            ...aliasOptions.map((email) => ({ label: email, value: email })),
          ]}
        />
      </SettingsCard>

      <SettingsCard>
        <SettingsSectionTitle>Behavior</SettingsSectionTitle>
        <SettingsSwitchRow
          label="Zero Signature"
          description="Automatically include “Sent with Zero” in outbound messages."
          value={form.todusSignature}
          onValueChange={(value) => updateForm({ todusSignature: value })}
        />
        <SettingsSwitchRow
          label="Auto Mark Read"
          description="Mark threads as read when opened."
          value={form.autoRead}
          onValueChange={(value) => updateForm({ autoRead: value })}
        />
        <SettingsSwitchRow
          label="Undo Send"
          description="Enable delayed send window with undo support."
          value={form.undoSendEnabled}
          onValueChange={(value) => updateForm({ undoSendEnabled: value })}
        />
        <SettingsSwitchRow
          label="Animations"
          description="Enable animated transitions in mail screens."
          value={form.animations}
          onValueChange={(value) => updateForm({ animations: value })}
        />
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
});
