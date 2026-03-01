/**
 * SettingsListScreen — settings navigation hub.
 * Equivalent to `/settings` on web with links to all settings sub-pages.
 *
 * Phase: N5 (stub for N1 navigation scaffold).
 */
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { SettingsStackParamList } from '../../app/navigation/types';
import { useTheme } from '../../shared/theme/ThemeContext';

type Props = NativeStackScreenProps<SettingsStackParamList, 'SettingsListScreen'>;

// Settings menu items matching web `/settings/*` routes
const SETTINGS_ITEMS: Array<{
    label: string;
    screen: keyof SettingsStackParamList;
    description: string;
}> = [
        { label: 'General', screen: 'SettingsGeneralScreen', description: 'Account preferences' },
        { label: 'Appearance', screen: 'SettingsAppearanceScreen', description: 'Theme & display' },
        { label: 'Connections', screen: 'SettingsConnectionsScreen', description: 'Email accounts' },
        { label: 'Labels', screen: 'SettingsLabelsScreen', description: 'Manage labels' },
        { label: 'Categories', screen: 'SettingsCategoriesScreen', description: 'Category settings' },
        { label: 'Notifications', screen: 'SettingsNotificationsScreen', description: 'Alert preferences' },
        { label: 'Privacy', screen: 'SettingsPrivacyScreen', description: 'Privacy controls' },
        { label: 'Security', screen: 'SettingsSecurityScreen', description: 'Security options' },
        { label: 'Shortcuts', screen: 'SettingsShortcutsScreen', description: 'Keyboard shortcuts' },
        { label: 'Danger Zone', screen: 'SettingsDangerZoneScreen', description: 'Account deletion' },
    ];

export function SettingsListScreen({ navigation }: Props) {
    const { colors } = useTheme();
    const insets = useSafeAreaInsets();

    return (
        <View style={[styles.container, { backgroundColor: colors.background }]}>
            <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
                <Text style={[styles.title, { color: colors.foreground }]}>Settings</Text>

                <View style={[styles.section, { backgroundColor: colors.card, borderColor: colors.border }]}>
                    {SETTINGS_ITEMS.map((item, index) => {
                        const isLast = index === SETTINGS_ITEMS.length - 1;
                        const isDangerZone = item.screen === 'SettingsDangerZoneScreen';
                        return (
                            <Pressable
                                key={item.screen}
                                style={[
                                    styles.settingsItem,
                                    !isLast && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.border },
                                ]}
                                onPress={() => navigation.navigate(item.screen as any)}
                            >
                                <View style={styles.settingsItemContent}>
                                    <Text
                                        style={[
                                            styles.settingsItemLabel,
                                            { color: isDangerZone ? colors.destructive : colors.foreground },
                                        ]}
                                    >
                                        {item.label}
                                    </Text>
                                    <Text style={[styles.settingsItemDescription, { color: colors.mutedForeground }]}>
                                        {item.description}
                                    </Text>
                                </View>
                                <Text style={[styles.chevron, { color: colors.mutedForeground }]}>›</Text>
                            </Pressable>
                        );
                    })}
                </View>
            </ScrollView>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    content: {
        padding: 16,
    },
    title: {
        fontSize: 28,
        fontWeight: '800',
        letterSpacing: -0.5,
        marginBottom: 20,
        marginTop: 8,
    },
    section: {
        borderRadius: 12,
        borderWidth: StyleSheet.hairlineWidth,
        overflow: 'hidden',
    },
    settingsItem: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 16,
        paddingVertical: 14,
    },
    settingsItemContent: {
        flex: 1,
        gap: 2,
    },
    settingsItemLabel: {
        fontSize: 16,
        fontWeight: '500',
    },
    settingsItemDescription: {
        fontSize: 13,
    },
    chevron: {
        fontSize: 22,
        fontWeight: '300',
        marginLeft: 8,
    },
});
