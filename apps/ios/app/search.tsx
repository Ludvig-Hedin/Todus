/**
 * Search screen — modal for searching across all emails.
 * Uses mail.listThreads with q parameter and debounced input.
 */
import { useRouter } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
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

const FOLDERS = [
  { id: 'inbox', label: 'Inbox' },
  { id: 'sent', label: 'Sent' },
  { id: 'draft', label: 'Drafts' },
  { id: 'archive', label: 'Archive' },
  { id: 'spam', label: 'Spam' },
  { id: 'bin', label: 'Trash' },
] as const;

export default function SearchScreen() {
  const router = useRouter();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [folder, setFolder] = useState<(typeof FOLDERS)[number]['id']>('inbox');
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [starredOnly, setStarredOnly] = useState(false);
  const [hasAttachment, setHasAttachment] = useState(false);
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

  const composedQuery = useMemo(() => {
    const parts: string[] = [];
    const trimmed = debouncedQuery.trim();
    if (trimmed) {
      parts.push(trimmed);
    }
    if (unreadOnly) {
      parts.push('is:unread');
    }
    if (starredOnly) {
      parts.push('is:starred');
    }
    if (hasAttachment) {
      parts.push('has:attachment');
    }
    return parts.join(' ');
  }, [debouncedQuery, unreadOnly, starredOnly, hasAttachment]);

  const hasStructuredFilters = unreadOnly || starredOnly || hasAttachment || folder !== 'inbox';
  const canSearch = debouncedQuery.trim().length >= 2 || hasStructuredFilters;

  const { data, isLoading } = useQuery({
    ...trpc.mail.listThreads.queryOptions({ q: composedQuery, folder }),
    enabled: canSearch,
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
            <Pressable
              onPress={() => {
                setQuery('');
                setDebouncedQuery('');
              }}
            >
              <X size={18} color={colors.mutedForeground} />
            </Pressable>
          )}
        </View>
        <Pressable onPress={() => router.back()}>
          <Text style={[styles.cancelText, { color: colors.primary }]}>Cancel</Text>
        </Pressable>
      </View>

      <View style={styles.filtersContainer}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.folderRow}
        >
          {FOLDERS.map((folderOption) => {
            const isActive = folder === folderOption.id;
            return (
              <Pressable
                key={folderOption.id}
                style={[
                  styles.filterChip,
                  {
                    backgroundColor: isActive ? colors.primary : colors.secondary,
                    borderColor: isActive ? colors.primary : colors.border,
                  },
                ]}
                onPress={() => setFolder(folderOption.id)}
              >
                <Text
                  style={[
                    styles.filterChipText,
                    { color: isActive ? colors.primaryForeground : colors.foreground },
                  ]}
                >
                  {folderOption.label}
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.quickFilterRow}
        >
          <Pressable
            style={[
              styles.quickFilterChip,
              {
                backgroundColor: unreadOnly ? colors.primary : colors.secondary,
                borderColor: unreadOnly ? colors.primary : colors.border,
              },
            ]}
            onPress={() => setUnreadOnly((prev) => !prev)}
          >
            <Text
              style={[
                styles.quickFilterText,
                { color: unreadOnly ? colors.primaryForeground : colors.foreground },
              ]}
            >
              Unread
            </Text>
          </Pressable>
          <Pressable
            style={[
              styles.quickFilterChip,
              {
                backgroundColor: starredOnly ? colors.primary : colors.secondary,
                borderColor: starredOnly ? colors.primary : colors.border,
              },
            ]}
            onPress={() => setStarredOnly((prev) => !prev)}
          >
            <Text
              style={[
                styles.quickFilterText,
                { color: starredOnly ? colors.primaryForeground : colors.foreground },
              ]}
            >
              Starred
            </Text>
          </Pressable>
          <Pressable
            style={[
              styles.quickFilterChip,
              {
                backgroundColor: hasAttachment ? colors.primary : colors.secondary,
                borderColor: hasAttachment ? colors.primary : colors.border,
              },
            ]}
            onPress={() => setHasAttachment((prev) => !prev)}
          >
            <Text
              style={[
                styles.quickFilterText,
                { color: hasAttachment ? colors.primaryForeground : colors.foreground },
              ]}
            >
              Attachment
            </Text>
          </Pressable>
        </ScrollView>
      </View>

      {/* Results */}
      <View style={styles.results}>
        {!canSearch ? (
          <View style={styles.hintContainer}>
            <Text style={[styles.hintText, { color: colors.mutedForeground }]}>
              Type at least 2 characters or select a filter to search
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
                  {debouncedQuery.trim().length > 0
                    ? `No results found for "${debouncedQuery.trim()}"`
                    : 'No results found with current filters'}
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
  filtersContainer: {
    gap: 8,
    paddingTop: 10,
    paddingBottom: 8,
  },
  folderRow: {
    gap: 8,
    paddingHorizontal: 16,
  },
  quickFilterRow: {
    gap: 8,
    paddingHorizontal: 16,
  },
  filterChip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  filterChipText: {
    fontSize: 13,
    fontWeight: '600',
  },
  quickFilterChip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  quickFilterText: {
    fontSize: 13,
    fontWeight: '600',
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
