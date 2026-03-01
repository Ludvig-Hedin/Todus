import React, { useState, useRef } from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';
import { WebView } from 'react-native-webview';
import { useTheme } from '../../shared/theme/ThemeContext';

export interface DummyMessage {
    id: string;
    sender: { name: string; email: string };
    date: string;
    bodyHtml: string;
}

interface MessageCardProps {
    message: DummyMessage;
}

export function MessageCard({ message }: MessageCardProps) {
    const { colors } = useTheme();
    const [webViewHeight, setWebViewHeight] = useState(100);

    const injectedJavaScript = `
        setTimeout(function() {
            window.ReactNativeWebView.postMessage(
                Math.max(
                    document.body.scrollHeight,
                    document.documentElement.scrollHeight,
                    document.body.offsetHeight,
                    document.documentElement.offsetHeight,
                    document.body.clientHeight,
                    document.documentElement.clientHeight
                ).toString()
            );
        }, 100);
        true;
    `;

    return (
        <View style={[styles.card, { backgroundColor: colors.background, borderColor: colors.border }]}>
            <View style={styles.header}>
                <View style={styles.senderContainer}>
                    <Text style={[styles.senderName, { color: colors.foreground }]}>{message.sender.name}</Text>
                    <Text style={[styles.senderEmail, { color: colors.mutedForeground }]}>
                        {'<'}{message.sender.email}{'>'}
                    </Text>
                </View>
                <Text style={[styles.date, { color: colors.mutedForeground }]}>{message.date}</Text>
            </View>

            <View style={{ height: webViewHeight, width: '100%' }}>
                <WebView
                    source={{
                        html: `<meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        body { 
                            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; 
                            font-size: 15px; 
                            line-height: 1.5; 
                            color: ${colors.foreground}; 
                            background-color: ${colors.background};
                            margin: 0;
                            padding: 0;
                            word-wrap: break-word;
                        }
                        a { color: ${colors.primary}; }
                    </style>
                    ${message.bodyHtml}`
                    }}
                    injectedJavaScript={injectedJavaScript}
                    onMessage={(event) => {
                        const height = parseInt(event.nativeEvent.data, 10);
                        if (!isNaN(height) && height > 0) {
                            setWebViewHeight(height);
                        }
                    }}
                    scrollEnabled={false}
                    showsVerticalScrollIndicator={false}
                    showsHorizontalScrollIndicator={false}
                    style={{ flex: 1, backgroundColor: 'transparent' }}
                    containerStyle={{ flex: 1, backgroundColor: 'transparent' }}
                />
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    card: {
        borderRadius: 12,
        borderWidth: StyleSheet.hairlineWidth,
        padding: 16,
        marginBottom: 16,
        gap: 16,
    },
    header: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'baseline',
    },
    senderContainer: {
        flex: 1,
        flexDirection: 'row',
        alignItems: 'baseline',
        gap: 6,
        flexWrap: 'wrap',
    },
    senderName: {
        fontSize: 16,
        fontWeight: '600',
    },
    senderEmail: {
        fontSize: 13,
    },
    date: {
        fontSize: 13,
    },
});
