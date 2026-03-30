/**
 * ThemeContext — provides semantic design tokens to all native screens.
 * Uses the shared web tokens, then derives a denser native surface system
 * so screens stay visually consistent without each one hardcoding shades.
 */
import { semanticColors, spacing, typography, radius, type ColorMode } from '@zero/design-tokens';
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
  const darkInk = '#f2f0eb';
  const lightInk = '#1f1d1a';
  const darkAccent = '#8d8479';
  const lightAccent = '#6f675e';

  return {
    canvas: isDark ? '#0b0b0c' : '#f6f5f2',
    surface: isDark ? '#111214' : '#ffffff',
    surfaceMuted: isDark ? '#17181a' : '#f0efea',
    surfaceRaised: isDark ? '#101113' : '#fbfaf7',
    surfaceInset: isDark ? '#0e0f11' : '#ebe9e3',
    borderSubtle: isDark ? withAlpha(darkInk, 0.08) : withAlpha(lightInk, 0.08),
    borderStrong: isDark ? withAlpha(darkInk, 0.14) : withAlpha(lightInk, 0.12),
    pressed: isDark ? '#202124' : '#e7e5de',
    accent: isDark ? darkAccent : lightAccent,
    accentSoft: isDark ? withAlpha(darkAccent, 0.2) : withAlpha(lightAccent, 0.12),
    accentMuted: isDark ? withAlpha(darkAccent, 0.12) : withAlpha(lightAccent, 0.08),
    avatar: isDark ? '#232428' : '#e6e3dc',
    avatarText: isDark ? darkInk : lightInk,
    shadow: isDark ? '#040405' : lightInk,
    overlay: isDark ? withAlpha('#0b0b0c', 0.72) : withAlpha(lightInk, 0.16),
    warning: isDark ? '#baa070' : '#876d3a',
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
