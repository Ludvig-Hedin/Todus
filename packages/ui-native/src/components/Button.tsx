import { getSemanticColor, radius, spacing } from '@zero/design-tokens';
import type { PropsWithChildren } from 'react';
import { Pressable, StyleSheet, Text, type PressableProps } from 'react-native';

type ButtonTone = 'primary' | 'secondary' | 'danger' | 'ghost';

type ButtonProps = PropsWithChildren<
  PressableProps & {
    tone?: ButtonTone;
    colorMode?: 'light' | 'dark';
  }
>;

export function Button({ children, tone = 'primary', colorMode = 'light', ...props }: ButtonProps) {
  const colorSet = getToneColors(tone, colorMode);
  const { style, ...rest } = props;

  return (
    <Pressable
      accessibilityRole="button"
      {...rest}
      style={(state) => [
        styles.base,
        { backgroundColor: colorSet.background },
        typeof style === 'function' ? style(state) : style,
      ]}
    >
      <Text style={[styles.text, { color: colorSet.foreground }]}>{children}</Text>
    </Pressable>
  );
}

function getToneColors(tone: ButtonTone, mode: 'light' | 'dark') {
  if (tone === 'secondary') {
    return {
      background: getSemanticColor(mode, 'secondary'),
      foreground: getSemanticColor(mode, 'secondaryForeground'),
    };
  }

  if (tone === 'danger') {
    return {
      background: getSemanticColor(mode, 'destructive'),
      foreground: getSemanticColor(mode, 'destructiveForeground'),
    };
  }

  if (tone === 'ghost') {
    return {
      background: 'transparent',
      foreground: getSemanticColor(mode, 'foreground'),
    };
  }

  return {
    background: getSemanticColor(mode, 'primary'),
    foreground: getSemanticColor(mode, 'primaryForeground'),
  };
}

const styles = StyleSheet.create({
  base: {
    minHeight: 44,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: spacing[4],
    borderRadius: radius.lg,
  },
  text: {
    fontSize: 14,
    fontWeight: '600',
  },
});
