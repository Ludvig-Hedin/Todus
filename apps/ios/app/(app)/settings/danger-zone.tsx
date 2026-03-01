import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsTextInput,
} from '../../../src/features/settings/SettingsUI';
import { clearSessionAtom } from '../../../src/shared/state/session';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { Alert, StyleSheet, Text, View } from 'react-native';
import { useMutation } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useSetAtom } from 'jotai';
import { useState } from 'react';

const CONFIRMATION_TEXT = 'DELETE';

export default function DangerZoneSettings() {
  const { colors } = useTheme();
  const router = useRouter();
  const trpc = useTRPC();
  const clearSession = useSetAtom(clearSessionAtom);
  const [confirmation, setConfirmation] = useState('');

  const deleteAccountMutation = useMutation(trpc.user.delete.mutationOptions());

  const deleteAccount = async () => {
    if (confirmation !== CONFIRMATION_TEXT) {
      Alert.alert('Confirmation required', `Type "${CONFIRMATION_TEXT}" to continue.`);
      return;
    }

    Alert.alert(
      'Delete account?',
      'This action is permanent and cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              const result = await deleteAccountMutation.mutateAsync();
              if (!result.success) {
                Alert.alert('Delete failed', result.message || 'Could not delete account.');
                return;
              }
              await clearSession();
              router.replace('/(auth)/login');
            } catch (error: any) {
              Alert.alert('Delete failed', error?.message || 'Could not delete account.');
            }
          },
        },
      ],
      { cancelable: true },
    );
  };

  return (
    <SettingsScreenContainer>
      <SettingsCard>
        <SettingsSectionTitle>Delete Account</SettingsSectionTitle>
        <SettingsDescription>
          This permanently deletes your account and all associated data. This operation cannot be
          reversed.
        </SettingsDescription>
        <View style={[styles.warning, { borderColor: colors.destructive }]}>
          <Text style={[styles.warningText, { color: colors.destructive }]}>
            Type "{CONFIRMATION_TEXT}" below to confirm.
          </Text>
        </View>
        <SettingsTextInput
          value={confirmation}
          onChangeText={setConfirmation}
          placeholder={CONFIRMATION_TEXT}
        />
      </SettingsCard>

      <SettingsButton
        label={deleteAccountMutation.isPending ? 'Deleting...' : 'Delete Account'}
        onPress={deleteAccount}
        variant="destructive"
        disabled={deleteAccountMutation.isPending}
      />
    </SettingsScreenContainer>
  );
}

const styles = StyleSheet.create({
  warning: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    padding: 10,
  },
  warningText: {
    fontSize: 13,
    fontWeight: '600',
  },
});
