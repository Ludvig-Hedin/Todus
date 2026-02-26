/**
 * Haptic feedback utility — wraps expo-haptics for consistent tactile feedback.
 * Gracefully degrades on simulator/platforms without haptic hardware.
 */
import * as Haptics from 'expo-haptics';

export const haptics = {
  /** Light tap — thread press, button tap */
  light: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {}),
  /** Medium tap — swipe action trigger */
  medium: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {}),
  /** Heavy tap — destructive action confirm */
  heavy: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy).catch(() => {}),
  /** Success — send email, archive */
  success: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {}),
  /** Warning — spam, unsaved changes */
  warning: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {}),
  /** Error — failed action */
  error: () => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error).catch(() => {}),
  /** Selection tick — toggling star, theme switch */
  selection: () => Haptics.selectionAsync().catch(() => {}),
};
