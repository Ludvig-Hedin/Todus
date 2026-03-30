/**
 * Appearance settings — color theme preference parity with web settings.
 */
import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsOptionGroup,
  SettingsScreenContainer,
  SettingsSectionTitle,
} from '../../../src/features/settings/SettingsUI';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ActivityIndicator, Alert, StyleSheet, Text, View } from 'react-native';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useEffect, useState } from 'react';

type ThemePreference = 'light' | 'dark' | 'system';

export default function AppearanceSettings() {
  const { colors, ui, colorMode } = useTheme();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery(trpc.settings.get.queryOptions());
  const [themePreference, setThemePreference] = useState<ThemePreference>('system');
  const [isDirty, setIsDirty] = useState(false);

  const saveMutation = useMutation({
    ...trpc.settings.save.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      setIsDirty(false);
    },
  });

  useEffect(() => {
    const settingTheme = settingsQuery.data?.settings?.colorTheme;
    if (!settingTheme) return;
    setThemePreference(settingTheme);
    setIsDirty(false);
  }, [settingsQuery.data?.settings?.colorTheme]);

  const saveChanges = async () => {
    try {
      await saveMutation.mutateAsync({
        colorTheme: themePreference,
      });
      Alert.alert('Saved', 'Appearance settings were updated.');
    } catch (error: any) {
      Alert.alert('Save failed', error?.message || 'Could not save appearance settings.');
    }
  };

  if (settingsQuery.isLoading) {
    return (
      <View style={[styles.loading, { backgroundColor: ui.canvas }]}>
        <ActivityIndicator color={colors.foreground} />
      </View>
    );
  }

  if (settingsQuery.isError) {
    return (
      <View style={[styles.loading, { backgroundColor: ui.canvas }]}>
        <View style={[styles.errorBox, { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle }]}>
          <Text style={{ color: colors.foreground, fontWeight: '600' }}>Could not load settings</Text>
          <Text style={{ color: colors.mutedForeground, marginTop: 4 }}>
            {(settingsQuery.error as Error | undefined)?.message ??
              'Appearance values may be out of date.'}
          </Text>
          <SettingsButton label="Retry" onPress={() => settingsQuery.refetch()} />
        </View>
      </View>
    );
  }

  return (
    <SettingsScreenContainer>
      <SettingsCard>
        <SettingsSectionTitle>Theme</SettingsSectionTitle>
        <SettingsDescription>
          Choose light, dark, or system theme. The current rendered mode is {colorMode}.
        </SettingsDescription>
        <SettingsOptionGroup
          value={themePreference}
          onSelect={(value) => {
            setThemePreference(value);
            setIsDirty(true);
          }}
          options={[
            { label: 'System', value: 'system' },
            { label: 'Light', value: 'light' },
            { label: 'Dark', value: 'dark' },
          ]}
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
  errorBox: {
    width: '100%',
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 12,
    padding: 16,
    gap: 8,
  },
});
