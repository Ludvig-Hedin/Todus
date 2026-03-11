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
          backgroundColor: ui.surfaceRaised,
          borderColor: ui.borderSubtle,
          shadowColor: ui.shadow,
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
          backgroundColor: ui.surface,
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
      trackColor={{ false: ui.surfaceMuted, true: colors.foreground }}
      thumbColor={value ? ui.surface : colors.foreground}
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
          backgroundColor: value ? ui.surface : ui.surfaceInset,
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
              backgroundColor: value ? colors.foreground : ui.surfaceMuted,
              borderColor: value ? colors.foreground : ui.borderSubtle,
            },
          ]}
        >
          <Text
            style={[
              styles.stateBadgeText,
              { color: value ? colors.background : colors.mutedForeground },
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
          backgroundColor: ui.surfaceMuted,
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
                backgroundColor: selected ? colors.foreground : ui.surface,
                borderColor: selected ? colors.foreground : ui.borderSubtle,
                marginBottom: isLast ? 0 : 6,
              },
            ]}
            onPress={() => onSelect(option.value)}
            accessibilityRole="radio"
            accessibilityState={{ selected }}
          >
            <Text
              style={[
                styles.optionLabel,
                { color: selected ? colors.background : colors.foreground },
              ]}
            >
              {option.label}
            </Text>
            <View
              style={[
                styles.optionIndicator,
                {
                  backgroundColor: selected ? colors.background : 'transparent',
                  borderColor: selected ? colors.background : ui.borderStrong,
                },
              ]}
            >
              {selected ? (
                <View
                  style={[styles.optionIndicatorInner, { backgroundColor: colors.foreground }]}
                />
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
  const backgroundColor =
    variant === 'primary'
      ? colors.foreground
      : variant === 'destructive'
        ? colors.destructive
        : ui.surface;
  const textColor =
    variant === 'primary'
      ? colors.background
      : variant === 'destructive'
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
              ? variant === 'primary'
                ? colors.mutedForeground
                : variant === 'destructive'
                  ? colors.destructive
                  : ui.surfaceInset
              : backgroundColor,
          borderColor:
            variant === 'primary' || variant === 'destructive' ? backgroundColor : ui.borderStrong,
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
    padding: 16,
    gap: 14,
  },
  card: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 22,
    padding: 16,
    gap: 12,
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.06,
    shadowRadius: 18,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  description: {
    fontSize: 12,
    lineHeight: 17,
  },
  fieldLabel: {
    fontSize: 13,
    fontWeight: '500',
  },
  input: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
  },
  row: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 11,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  rowText: {
    flex: 1,
    gap: 4,
  },
  rowTrailing: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  rowLabel: {
    fontSize: 14,
    fontWeight: '500',
  },
  rowDescription: {
    fontSize: 12,
    lineHeight: 16,
  },
  stateBadge: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 5,
    minWidth: 42,
    alignItems: 'center',
  },
  stateBadgeText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.2,
    textTransform: 'uppercase',
  },
  optionGroup: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
    padding: 6,
  },
  optionRow: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    minHeight: 52,
    paddingHorizontal: 14,
    paddingVertical: 12,
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
    width: 20,
    height: 20,
    borderRadius: 999,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
  },
  optionIndicatorInner: {
    width: 8,
    height: 8,
    borderRadius: 999,
  },
  button: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 14,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '600',
  },
});
