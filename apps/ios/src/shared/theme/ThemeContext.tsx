/**
 * ThemeContext — provides semantic design tokens to all native screens.
 * Uses the shared web tokens, then derives a denser native surface system
 * so screens stay visually consistent without each one hardcoding shades.
 */
import {
  semanticColors,
  spacing,
  typography,
  radius,
  type ColorMode,
} from '@zero/design-tokens';
import { createContext, useContext, useMemo, type PropsWithChildren } from 'react';
import { useColorScheme } from 'react-native';

type NativeUiTokens = {
  canvas: string;
  surface: string;
  surfaceMuted: string;
  surfaceRaised: string;
  surfaceInset: string;
  borderSubtle: string;
  borderStrong: string;
  pressed: string;
  accent: string;
  accentSoft: string;
  accentMuted: string;
  avatar: string;
  avatarText: string;
  shadow: string;
  overlay: string;
  warning: string;
};

export type ThemeContextValue = {
  colorMode: ColorMode;
  colors: typeof semanticColors.light | typeof semanticColors.dark;
  spacing: typeof spacing;
  typography: typeof typography;
  radius: typeof radius;
  ui: NativeUiTokens;
  isDark: boolean;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: PropsWithChildren) {
  const systemColorScheme = useColorScheme();
  const colorMode: ColorMode = systemColorScheme === 'dark' ? 'dark' : 'light';

  const value = useMemo<ThemeContextValue>(
    () => ({
      colorMode,
      colors: semanticColors[colorMode],
      spacing,
      typography,
      radius,
      ui: createNativeUiTokens(colorMode),
      isDark: colorMode === 'dark',
    }),
    [colorMode],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return ctx;
}

function createNativeUiTokens(colorMode: ColorMode): NativeUiTokens {
  const isDark = colorMode === 'dark';

  return {
    canvas: isDark ? '#090b0e' : '#f3f2ef',
    surface: isDark ? '#111418' : '#fbfaf7',
    surfaceMuted: isDark ? '#161a1f' : '#f1efea',
    surfaceRaised: isDark ? '#1b2026' : '#ffffff',
    surfaceInset: isDark ? '#0d1014' : '#ece8e1',
    borderSubtle: isDark ? withAlpha('#ffffff', 0.08) : withAlpha('#111827', 0.08),
    borderStrong: isDark ? withAlpha('#ffffff', 0.14) : withAlpha('#111827', 0.12),
    pressed: isDark ? '#21262d' : '#e8e5de',
    accent: isDark ? '#8ba0dd' : '#5d74ba',
    accentSoft: isDark ? withAlpha('#8ba0dd', 0.2) : withAlpha('#5d74ba', 0.12),
    accentMuted: isDark ? withAlpha('#8ba0dd', 0.12) : withAlpha('#5d74ba', 0.07),
    avatar: isDark ? '#232932' : '#e9e5de',
    avatarText: isDark ? '#f3f3f1' : '#252a31',
    shadow: isDark ? '#050608' : '#111827',
    overlay: isDark ? withAlpha('#090b0e', 0.72) : withAlpha('#111827', 0.16),
    warning: isDark ? '#b9a06a' : '#8b7242',
  };
}

function withAlpha(hex: string, alpha: number): string {
  const normalized = hex.replace('#', '');
  const safeHex =
    normalized.length === 3
      ? normalized
        .split('')
        .map((char) => `${char}${char}`)
        .join('')
      : normalized;

  const red = parseInt(safeHex.slice(0, 2), 16);
  const green = parseInt(safeHex.slice(2, 4), 16);
  const blue = parseInt(safeHex.slice(4, 6), 16);

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}
