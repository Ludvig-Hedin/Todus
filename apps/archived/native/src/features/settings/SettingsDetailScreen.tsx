/**
 * SettingsDetailScreen — generic placeholder for individual settings pages.
 * Each will be replaced with a purpose-built screen in N5.
 *
 * Used for: General, Appearance, Connections, Labels, Categories,
 * Notifications, Privacy, Security, Shortcuts, Danger Zone.
 */
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../shared/theme/ThemeContext';

type Props = {
    route: { name: string };
};

/** Extracts a readable label from the screen name, e.g. 'SettingsGeneralScreen' → 'General' */
function labelFromScreenName(name: string): string {
    return name
        .replace(/^Settings/, '')
        .replace(/Screen$/, '')
        .replace(/([A-Z])/g, ' $1')
        .trim();
}

export function SettingsDetailScreen({ route }: Props) {
    const { colors } = useTheme();
    const insets = useSafeAreaInsets();
    const label = labelFromScreenName(route.name);

    return (
        <View style={[styles.container, { backgroundColor: colors.background }]}>
            <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
                <Text style={[styles.title, { color: colors.foreground }]}>{label}</Text>
                <View style={[styles.placeholder, { backgroundColor: colors.card, borderColor: colors.border }]}>
                    <Text style={[styles.placeholderText, { color: colors.mutedForeground }]}>
                        Settings form for "{label}" will be implemented in N5.
                    </Text>
                    <Text style={[styles.placeholderDetail, { color: colors.mutedForeground }]}>
                        This screen will use the same tRPC settings.* mutations as the web app.
                    </Text>
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
        fontSize: 24,
        fontWeight: '700',
        marginBottom: 16,
        marginTop: 8,
    },
    placeholder: {
        padding: 24,
        borderRadius: 12,
        borderWidth: StyleSheet.hairlineWidth,
        alignItems: 'center',
        gap: 8,
    },
    placeholderText: {
        fontSize: 14,
        textAlign: 'center',
    },
    placeholderDetail: {
        fontSize: 12,
        textAlign: 'center',
    },
});
