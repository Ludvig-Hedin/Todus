import { getSemanticColor, spacing, typography } from '@zero/design-tokens';
import type { PropsWithChildren } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

type ScreenProps = PropsWithChildren<{
  title: string;
  subtitle?: string;
  colorMode?: 'light' | 'dark';
}>;

export function Screen({ title, subtitle, children, colorMode = 'light' }: ScreenProps) {
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={[
        styles.container,
        { backgroundColor: getSemanticColor(colorMode, 'background') },
      ]}
    >
      <View style={styles.header}>
        <Text style={[styles.title, { color: getSemanticColor(colorMode, 'foreground') }]}>{title}</Text>
        {subtitle ? (
          <Text style={[styles.subtitle, { color: getSemanticColor(colorMode, 'mutedForeground') }]}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      <View style={styles.content}>{children}</View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    padding: spacing[4],
    gap: spacing[4],
  },
  header: {
    gap: spacing[1],
  },
  title: {
    fontSize: typography.size['2xl'],
    lineHeight: typography.lineHeight['2xl'],
    fontWeight: '700',
  },
  subtitle: {
    fontSize: typography.size.md,
    lineHeight: typography.lineHeight.md,
  },
  content: {
    gap: spacing[3],
  },
});
