/**
 * Search screen — modal for searching across all emails.
 * Uses mail.listThreads with q parameter and debounced input.
 */
import { useRouter } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import { X } from 'lucide-react-native';
import { useQuery } from '@tanstack/react-query';
import { useTheme } from '../src/shared/theme/ThemeContext';
import { useTRPC } from '../src/providers/QueryTrpcProvider';
import { ThreadListItem } from '../src/features/mail/ThreadListItem';

export default function SearchScreen() {
  const router = useRouter();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Proper debounce: clear previous timer on every keystroke, only fire after 300ms of inactivity
  const handleChangeText = useCallback((text: string) => {
    setQuery(text);
    if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    debounceTimerRef.current = setTimeout(() => setDebouncedQuery(text), 300);
  }, []);

  // Cleanup timer on unmount to prevent memory leak
  useEffect(() => {
    return () => {
      if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    };
  }, []);

  const { data, isLoading } = useQuery({
    ...trpc.mail.listThreads.queryOptions({ q: debouncedQuery, folder: 'inbox' }),
    enabled: debouncedQuery.length >= 2,
  });

  const threads = useMemo(() => data?.threads ?? [], [data?.threads]);

  const handleThreadPress = useCallback(
    (threadId: string) => {
      router.push({
        pathname: '/(app)/(mail)/thread/[threadId]',
        params: { threadId },
      });
    },
    [router],
  );

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Search header */}
      <View style={[styles.header, { paddingTop: insets.top + 8, borderBottomColor: colors.border }]}>
        <View style={[styles.searchBar, { backgroundColor: colors.secondary }]}>
          <TextInput
            style={[styles.searchInput, { color: colors.foreground }]}
            placeholder="Search emails..."
            placeholderTextColor={colors.mutedForeground}
            value={query}
            onChangeText={handleChangeText}
            autoFocus
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="search"
          />
          {query.length > 0 && (
            <Pressable onPress={() => { setQuery(''); setDebouncedQuery(''); }}>
              <X size={18} color={colors.mutedForeground} />
            </Pressable>
          )}
        </View>
        <Pressable onPress={() => router.back()}>
          <Text style={[styles.cancelText, { color: colors.primary }]}>Cancel</Text>
        </Pressable>
      </View>

      {/* Results */}
      <View style={styles.results}>
        {debouncedQuery.length < 2 ? (
          <View style={styles.hintContainer}>
            <Text style={[styles.hintText, { color: colors.mutedForeground }]}>
              Type at least 2 characters to search
            </Text>
          </View>
        ) : isLoading ? (
          <View style={styles.loadingContainer}>
            <ActivityIndicator color={colors.primary} />
          </View>
        ) : (
          <FlashList
            data={threads}
            {...({ estimatedItemSize: 80 } as any)}
            keyExtractor={(item: any) => item.id}
            renderItem={({ item }: { item: any }) => (
              <ThreadListItem threadId={item.id} onPress={handleThreadPress} />
            )}
            ListEmptyComponent={
              <View style={styles.emptyContainer}>
                <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
                  No results found for "{debouncedQuery}"
                </Text>
              </View>
            }
          />
        )}
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
    paddingHorizontal: 16,
    paddingBottom: 12,
    gap: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  searchBar: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 10,
    paddingHorizontal: 12,
    height: 40,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    padding: 0,
  },
  cancelText: {
    fontSize: 16,
  },
  results: {
    flex: 1,
  },
  hintContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 48,
  },
  hintText: {
    fontSize: 15,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 48,
  },
  emptyContainer: {
    alignItems: 'center',
    paddingVertical: 48,
    paddingHorizontal: 24,
  },
  emptyText: {
    fontSize: 15,
    textAlign: 'center',
  },
});
