/**
 * ComposeScreen — compose new email or reply/forward.
 * Equivalent to `/mail/compose` on web.
 *
 * Phase: N4 (stub for N1 navigation scaffold).
 */
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { RootStackParamList } from '../../app/navigation/types';
import { useTheme } from '../../shared/theme/ThemeContext';

type Props = NativeStackScreenProps<RootStackParamList, 'ComposeModal'>;

export function ComposeScreen({ navigation }: Props) {
    const { colors } = useTheme();
    const insets = useSafeAreaInsets();

    return (
        <View style={[styles.container, { backgroundColor: colors.background, paddingTop: insets.top }]}>
            {/* Header */}
            <View style={[styles.header, { borderBottomColor: colors.border }]}>
                <Pressable onPress={() => navigation.goBack()}>
                    <Text style={[styles.cancelText, { color: colors.primary }]}>Cancel</Text>
                </Pressable>
                <Text style={[styles.headerTitle, { color: colors.foreground }]}>New Message</Text>
                <Pressable
                    style={[styles.sendButton, { backgroundColor: colors.primary }]}
                    onPress={() => {
                        // Send will be implemented in N4
                        navigation.goBack();
                    }}
                >
                    <Text style={[styles.sendText, { color: colors.primaryForeground }]}>Send</Text>
                </Pressable>
            </View>

            {/* Compose form — placeholder fields */}
            <View style={styles.form}>
                <View style={[styles.fieldRow, { borderBottomColor: colors.border }]}>
                    <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>To:</Text>
                    <TextInput
                        style={[styles.fieldInput, { color: colors.foreground }]}
                        placeholderTextColor={colors.mutedForeground}
                        placeholder="Recipients"
                    />
                </View>
                <View style={[styles.fieldRow, { borderBottomColor: colors.border }]}>
                    <Text style={[styles.fieldLabel, { color: colors.mutedForeground }]}>Subject:</Text>
                    <TextInput
                        style={[styles.fieldInput, { color: colors.foreground }]}
                        placeholderTextColor={colors.mutedForeground}
                        placeholder="Subject"
                    />
                </View>
                <View style={styles.bodyContainer}>
                    <TextInput
                        style={[styles.bodyInput, { color: colors.foreground }]}
                        placeholderTextColor={colors.mutedForeground}
                        placeholder="Write your message..."
                        multiline
                        textAlignVertical="top"
                    />
                    <Text style={[styles.placeholderNote, { color: colors.mutedForeground }]}>
                        Rich text editor (@10play/tentap-editor) will be integrated in N4
                    </Text>
                </View>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: 16,
        paddingVertical: 12,
        borderBottomWidth: StyleSheet.hairlineWidth,
    },
    cancelText: {
        fontSize: 16,
    },
    headerTitle: {
        fontSize: 17,
        fontWeight: '600',
    },
    sendButton: {
        paddingHorizontal: 16,
        paddingVertical: 8,
        borderRadius: 8,
    },
    sendText: {
        fontSize: 15,
        fontWeight: '600',
    },
    form: {
        flex: 1,
    },
    fieldRow: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 16,
        paddingVertical: 12,
        borderBottomWidth: StyleSheet.hairlineWidth,
    },
    fieldLabel: {
        fontSize: 15,
        width: 60,
    },
    fieldInput: {
        flex: 1,
        fontSize: 15,
        padding: 0,
    },
    bodyContainer: {
        flex: 1,
        padding: 16,
    },
    bodyInput: {
        flex: 1,
        fontSize: 15,
        lineHeight: 22,
    },
    placeholderNote: {
        fontSize: 11,
        textAlign: 'center',
        marginTop: 16,
    },
});
