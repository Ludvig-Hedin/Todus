/**
 * ErrorBoundary — catches React render errors and shows a recovery UI.
 * Prevents the entire app from crashing on component-level errors.
 */
import React, { Component, type ErrorInfo, type PropsWithChildren } from 'react';
import { Pressable, StyleSheet, Text, View, useColorScheme } from 'react-native';
import { semanticColors } from '@zero/design-tokens';

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<PropsWithChildren<{ fallback?: React.ReactNode }>, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('[ErrorBoundary]', error, errorInfo.componentStack);
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;
      return <ErrorFallback error={this.state.error} onRetry={this.handleRetry} />;
    }
    return this.props.children;
  }
}

function ErrorFallback({ error, onRetry }: { error: Error | null; onRetry: () => void }) {
  const scheme = useColorScheme();
  const colors = scheme === 'dark' ? semanticColors.dark : semanticColors.light;

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text style={[styles.title, { color: colors.foreground }]}>Something went wrong</Text>
      <Text style={[styles.message, { color: colors.mutedForeground }]} numberOfLines={4}>
        {error?.message || 'An unexpected error occurred.'}
      </Text>
      <Pressable
        style={[styles.retryButton, { backgroundColor: colors.primary }]}
        onPress={onRetry}
      >
        <Text style={[styles.retryText, { color: colors.primaryForeground }]}>Try Again</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    gap: 12,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
  },
  message: {
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 20,
  },
  retryButton: {
    marginTop: 8,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
  },
  retryText: {
    fontSize: 15,
    fontWeight: '600',
  },
});
