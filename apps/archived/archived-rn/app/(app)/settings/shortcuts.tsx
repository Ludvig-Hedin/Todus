import {
  SettingsCard,
  SettingsDescription,
  SettingsScreenContainer,
  SettingsSectionTitle,
} from '../../../src/features/settings/SettingsUI';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { typography } from '@zero/design-tokens';
import { StyleSheet, Text, View } from 'react-native';

const SHORTCUTS_BY_SCOPE = {
  navigation: [
    { action: 'Go to drafts', keys: ['G', 'D'] },
    { action: 'Go to inbox', keys: ['G', 'I'] },
    { action: 'Go to sent mail', keys: ['G', 'T'] },
    { action: 'Go to archive', keys: ['G', 'A'] },
    { action: 'Go to bin', keys: ['G', 'B'] },
  ],
  global: [
    { action: 'Undo last action', keys: ['Cmd/Ctrl', 'Z'] },
    { action: 'Compose new email', keys: ['C'] },
    { action: 'Open command palette', keys: ['Cmd/Ctrl', 'K'] },
    { action: 'Clear all filters', keys: ['Cmd/Ctrl', 'Shift', 'F'] },
  ],
  mail: [
    { action: 'Mark as read', keys: ['R'] },
    { action: 'Mark as unread', keys: ['U'] },
    { action: 'Archive', keys: ['E'] },
    { action: 'Delete', keys: ['D'] },
    { action: 'Star', keys: ['S'] },
    { action: 'Select all', keys: ['Cmd/Ctrl', 'A'] },
  ],
  compose: [
    { action: 'Send email', keys: ['Cmd/Ctrl', 'Enter'] },
    { action: 'Close compose', keys: ['Esc'] },
  ],
} as const;

export default function ShortcutsSettings() {
  const { colors } = useTheme();

  return (
    <SettingsScreenContainer>
      {Object.entries(SHORTCUTS_BY_SCOPE).map(([scope, shortcuts]) => (
        <SettingsCard key={scope}>
          <SettingsSectionTitle>{scope}</SettingsSectionTitle>
          <SettingsDescription>
            Shortcut customization is read-only for now; this mirrors the current web behavior.
          </SettingsDescription>
          {shortcuts.map((shortcut) => (
            <View
              key={`${scope}-${shortcut.action}`}
              style={[styles.row, { borderColor: colors.border }]}
            >
              <Text style={[styles.actionLabel, { color: colors.foreground }]}>
                {shortcut.action}
              </Text>
              <View style={styles.keys}>
                {shortcut.keys.map((key) => (
                  <View key={key} style={[styles.keycap, { backgroundColor: colors.secondary }]}>
                    <Text style={[styles.keyText, { color: colors.secondaryForeground }]}>
                      {key}
                    </Text>
                  </View>
                ))}
              </View>
            </View>
          ))}
        </SettingsCard>
      ))}
    </SettingsScreenContainer>
  );
}

const styles = StyleSheet.create({
  row: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  actionLabel: {
    fontSize: typography.size.sm,
    fontWeight: '500',
    flex: 1,
  },
  keys: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: 6,
  },
  keycap: {
    borderRadius: 6,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  keyText: {
    fontSize: typography.size.xs,
    fontWeight: '600',
  },
});
