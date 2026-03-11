import { getSemanticColor, radius, spacing } from '@zero/design-tokens';
import type { PropsWithChildren } from 'react';
import { Pressable, StyleSheet, Text, View, ActivityIndicator, type PressableProps } from 'react-native';

type ButtonTone = 'primary' | 'secondary' | 'destructive' | 'outline' | 'ghost';

type ButtonProps = PropsWithChildren<
  PressableProps & {
    tone?: ButtonTone;
    colorMode?: 'light' | 'dark';
    isLoading?: boolean;
    loadingText?: string;
    icon?: React.ReactNode;
    textStyle?: any;
  }
>;

export function Button({
  children,
  tone = 'primary',
  colorMode = 'light',
  isLoading = false,
  loadingText,
  icon,
  textStyle,
  ...props
}: ButtonProps) {
  const colorSet = getToneColors(tone, colorMode);
  const { style, ...rest } = props;

  const content = isLoading ? loadingText || children : children;

  return (
    <Pressable
      accessibilityRole="button"
      disabled={isLoading || props.disabled}
      {...rest}
      style={(state) => [
        styles.base,
        {
          backgroundColor: colorSet.background,
          borderColor: colorSet.border,
          borderWidth: tone === 'outline' ? 1 : 0,
          opacity: isLoading || props.disabled ? 0.7 : 1,
        },
        typeof style === 'function' ? style(state) : style,
      ]}
    >
      {isLoading ? (
        <ActivityIndicator size="small" color={colorSet.foreground} style={styles.icon} />
      ) : icon ? (
        <View style={styles.icon}>{icon as any}</View>
      ) : null}
      {typeof content === 'string' || typeof content === 'number' ? (
        <Text style={[styles.text, { color: colorSet.foreground }, textStyle]}>{content}</Text>
      ) : (
        <>{content}</>
      )}
    </Pressable>
  );
}

function getToneColors(tone: ButtonTone, mode: 'light' | 'dark') {
  if (tone === 'secondary') {
    return {
      background: getSemanticColor(mode, 'secondary'),
      foreground: getSemanticColor(mode, 'secondaryForeground'),
      border: 'transparent',
    };
  }

  if (tone === 'destructive') {
    return {
      background: getSemanticColor(mode, 'destructive'),
      foreground: getSemanticColor(mode, 'destructiveForeground'),
      border: 'transparent',
    };
  }

  if (tone === 'outline') {
    return {
      background: getSemanticColor(mode, 'background'),
      foreground: getSemanticColor(mode, 'foreground'),
      border: getSemanticColor(mode, 'input'),
    };
  }

  if (tone === 'ghost') {
    return {
      background: 'transparent',
      foreground: getSemanticColor(mode, 'foreground'),
      border: 'transparent',
    };
  }

  return {
    background: getSemanticColor(mode, 'primary'),
    foreground: getSemanticColor(mode, 'primaryForeground'),
    border: 'transparent',
  };
}

const styles = StyleSheet.create({
  base: {
    minHeight: 44,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: spacing[4],
    borderRadius: radius.lg,
  },
  text: {
    fontSize: 14,
    fontWeight: '500',
  },
  icon: {
    marginRight: spacing[2],
  },
});
