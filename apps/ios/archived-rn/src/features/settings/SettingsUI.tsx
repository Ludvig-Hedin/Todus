import { Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../shared/theme/ThemeContext';
import { ReactNode } from 'react';

export function SettingsScreenContainer({ children }: { children: ReactNode }) {
  const { ui } = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <View style={[styles.container, { backgroundColor: ui.canvas }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 24 }]}>
        {children}
      </ScrollView>
    </View>
  );
}

export function SettingsCard({ children }: { children: ReactNode }) {
  const { ui } = useTheme();
  return (
    <View
      style={[
        styles.card,
        {
          borderColor: ui.borderSubtle,
        },
      ]}
    >
      {children}
    </View>
  );
}

export function SettingsSectionTitle({ children }: { children: ReactNode }) {
  const { colors } = useTheme();
  return <Text style={[styles.sectionTitle, { color: colors.foreground }]}>{children}</Text>;
}

export function SettingsDescription({ children }: { children: ReactNode }) {
  const { colors } = useTheme();
  return <Text style={[styles.description, { color: colors.mutedForeground }]}>{children}</Text>;
}

export function SettingsFieldLabel({ children }: { children: ReactNode }) {
  const { colors } = useTheme();
  return <Text style={[styles.fieldLabel, { color: colors.foreground }]}>{children}</Text>;
}

export function SettingsTextInput({
  value,
  onChangeText,
  placeholder,
}: {
  value: string;
  onChangeText: (value: string) => void;
  placeholder?: string;
}) {
  const { colors, ui } = useTheme();
  return (
    <TextInput
      value={value}
      onChangeText={onChangeText}
      placeholder={placeholder}
      placeholderTextColor={colors.mutedForeground}
      style={[
        styles.input,
        {
          color: colors.foreground,
          backgroundColor: ui.surfaceMuted,
          borderColor: ui.borderStrong,
        },
      ]}
    />
  );
}

export function SettingsToggle({
  value,
  onValueChange,
}: {
  value: boolean;
  onValueChange: (value: boolean) => void;
}) {
  const { colors, ui } = useTheme();

  return (
    <Switch
      value={value}
      onValueChange={onValueChange}
      ios_backgroundColor={ui.surfaceMuted}
      trackColor={{ false: ui.surfaceMuted, true: ui.accent }}
      thumbColor={value ? '#f3f1ec' : '#d9d5cf'}
    />
  );
}

export function SettingsSwitchRow({
  label,
  description,
  value,
  onValueChange,
}: {
  label: string;
  description?: string;
  value: boolean;
  onValueChange: (value: boolean) => void;
}) {
  const { colors, ui } = useTheme();
  return (
    <View
      style={[
        styles.row,
        {
          borderColor: value ? ui.borderStrong : ui.borderSubtle,
          backgroundColor: value ? ui.surfaceMuted : 'transparent',
        },
      ]}
    >
      <View style={styles.rowText}>
        <Text style={[styles.rowLabel, { color: colors.foreground }]}>{label}</Text>
        {description ? (
          <Text style={[styles.rowDescription, { color: colors.mutedForeground }]}>
            {description}
          </Text>
        ) : null}
      </View>
      <View style={styles.rowTrailing}>
        <View
          style={[
            styles.stateBadge,
            {
              backgroundColor: value ? ui.accentSoft : ui.surfaceMuted,
              borderColor: value ? ui.accent : ui.borderSubtle,
            },
          ]}
        >
          <Text
            style={[
              styles.stateBadgeText,
              { color: value ? colors.foreground : colors.mutedForeground },
            ]}
          >
            {value ? 'On' : 'Off'}
          </Text>
        </View>
        <SettingsToggle value={value} onValueChange={onValueChange} />
      </View>
    </View>
  );
}

export function SettingsOptionGroup<T extends string>({
  value,
  options,
  onSelect,
}: {
  value: T;
  options: Array<{ label: string; value: T }>;
  onSelect: (value: T) => void;
}) {
  const { colors, ui } = useTheme();

  return (
    <View
      style={[
        styles.optionGroup,
        {
          borderColor: ui.borderSubtle,
          backgroundColor: 'transparent',
        },
      ]}
    >
      {options.map((option, index) => {
        const selected = option.value === value;
        const isLast = index === options.length - 1;
        return (
          <Pressable
            key={option.value}
            style={[
              styles.optionRow,
              {
                backgroundColor: selected ? ui.accentSoft : ui.surfaceMuted,
                borderColor: selected ? ui.accent : ui.borderSubtle,
                marginBottom: isLast ? 0 : 6,
              },
            ]}
            onPress={() => onSelect(option.value)}
            accessibilityRole="radio"
            accessibilityState={{ selected }}
          >
            <Text style={[styles.optionLabel, { color: colors.foreground }]}>{option.label}</Text>
            <View
              style={[
                styles.optionIndicator,
                {
                  backgroundColor: selected ? ui.accent : 'transparent',
                  borderColor: selected ? ui.accent : ui.borderStrong,
                },
              ]}
            >
              {selected ? (
                <View style={[styles.optionIndicatorInner, { backgroundColor: '#f3f1ec' }]} />
              ) : null}
            </View>
          </Pressable>
        );
      })}
    </View>
  );
}

export function SettingsButton({
  label,
  onPress,
  variant = 'primary',
  disabled = false,
}: {
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary' | 'destructive';
  disabled?: boolean;
}) {
  const { colors, ui } = useTheme();
  const isPrimary = variant === 'primary';
  const isDestructive = variant === 'destructive';
  const backgroundColor = isPrimary
    ? colors.primary
    : isDestructive
      ? colors.destructive
      : ui.surfaceMuted;
  const textColor = isPrimary
    ? colors.primaryForeground
    : isDestructive
      ? colors.destructiveForeground
      : colors.foreground;

  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        {
          backgroundColor:
            pressed && !disabled
              ? isPrimary
                ? ui.accent
                : isDestructive
                  ? colors.destructive
                  : ui.pressed
              : backgroundColor,
          borderColor: isPrimary || isDestructive ? backgroundColor : ui.borderSubtle,
          opacity: disabled ? 0.5 : 1,
        },
      ]}
    >
      <Text style={[styles.buttonText, { color: textColor }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: {
    paddingHorizontal: 20,
    paddingTop: 14,
    gap: 24,
  },
  card: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingBottom: 20,
    gap: 12,
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.2,
  },
  description: {
    fontSize: 13,
    lineHeight: 19,
  },
  fieldLabel: {
    fontSize: 13,
    fontWeight: '600',
  },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 15,
    paddingHorizontal: 14,
    paddingVertical: 11,
    fontSize: 14,
  },
  row: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
    paddingHorizontal: 14,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  rowText: {
    flex: 1,
    gap: 3,
  },
  rowTrailing: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  rowLabel: {
    fontSize: 14,
    fontWeight: '600',
  },
  rowDescription: {
    fontSize: 12,
    lineHeight: 15,
  },
  stateBadge: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
    minWidth: 42,
    alignItems: 'center',
  },
  stateBadgeText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.1,
    textTransform: 'uppercase',
  },
  optionGroup: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 20,
    padding: 0,
    overflow: 'hidden',
  },
  optionRow: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    minHeight: 54,
    paddingHorizontal: 16,
    paddingVertical: 13,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  optionLabel: {
    fontSize: 14,
    fontWeight: '600',
  },
  optionIndicator: {
    width: 18,
    height: 18,
    borderRadius: 999,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
  },
  optionIndicatorInner: {
    width: 6,
    height: 6,
    borderRadius: 999,
  },
  button: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 15,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '600',
  },
});
