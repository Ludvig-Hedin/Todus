import { getSemanticColor, radius, spacing, typography } from '@zero/design-tokens';
import type { ComponentProps } from 'react';
import { StyleSheet, TextInput } from 'react-native';

type TextFieldProps = ComponentProps<typeof TextInput> & {
  colorMode?: 'light' | 'dark';
};

export function TextField({ colorMode = 'light', ...props }: TextFieldProps) {
  return (
    <TextInput
      {...props}
      placeholderTextColor={getSemanticColor(colorMode, 'mutedForeground')}
      style={[
        styles.input,
        {
          color: getSemanticColor(colorMode, 'foreground'),
          borderColor: getSemanticColor(colorMode, 'border'),
          backgroundColor: getSemanticColor(colorMode, 'background'),
        },
        props.style,
      ]}
    />
  );
}

const styles = StyleSheet.create({
  input: {
    minHeight: 44,
    borderWidth: 1,
    borderRadius: radius.md,
    paddingHorizontal: spacing[3],
    paddingVertical: spacing[2],
    fontSize: typography.size.md,
    lineHeight: typography.lineHeight.md,
  },
});
