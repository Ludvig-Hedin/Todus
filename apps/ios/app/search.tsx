/**
 * Search screen — modal for searching across all emails.
 * Uses mail.listThreads with q parameter and debounced input.
 */
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ThreadListItem } from '../src/features/mail/ThreadListItem';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTRPC } from '../src/providers/QueryTrpcProvider';
import { useTheme } from '../src/shared/theme/ThemeContext';
import { useQuery } from '@tanstack/react-query';
import { FlashList } from '@shopify/flash-list';
import { X } from 'lucide-react-native';
import { useRouter } from 'expo-router';

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
  const { colors, ui } = useTheme();
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
  const activeFilterCount =
    (query.trim().length > 0 ? 1 : 0) +
    (folder !== 'inbox' ? 1 : 0) +
    (unreadOnly ? 1 : 0) +
    (starredOnly ? 1 : 0) +
    (hasAttachment ? 1 : 0);
  const activeFilterSummary = [
    query.trim().length > 0 ? `Query: ${query.trim()}` : null,
    folder !== 'inbox' ? `Folder: ${FOLDERS.find((item) => item.id === folder)?.label}` : null,
    unreadOnly ? 'Unread' : null,
    starredOnly ? 'Starred' : null,
    hasAttachment ? 'Attachment' : null,
  ]
    .filter(Boolean)
    .join(' · ');

  const clearAllFilters = useCallback(() => {
    setQuery('');
    setDebouncedQuery('');
    setFolder('inbox');
    setUnreadOnly(false);
    setStarredOnly(false);
    setHasAttachment(false);
  }, []);

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
    <View style={[styles.container, { backgroundColor: ui.canvas }]}>
      <View
        style={[styles.header, { paddingTop: insets.top + 8, borderBottomColor: ui.borderSubtle }]}
      >
        <View
          style={[
            styles.searchBar,
            {
              backgroundColor: ui.surfaceRaised,
              borderColor: ui.borderSubtle,
            },
          ]}
        >
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
        <Pressable
          style={[
            styles.cancelButton,
            { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
          ]}
          onPress={() => router.back()}
        >
          <Text style={[styles.cancelText, { color: colors.foreground }]}>Close</Text>
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
                    backgroundColor: isActive ? ui.accentSoft : ui.surface,
                    borderColor: isActive ? ui.accentMuted : ui.borderSubtle,
                  },
                ]}
                onPress={() => setFolder(folderOption.id)}
              >
                <Text
                  style={[
                    styles.filterChipText,
                    { color: isActive ? colors.foreground : colors.foreground },
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
                backgroundColor: unreadOnly ? ui.accentSoft : ui.surface,
                borderColor: unreadOnly ? ui.accentMuted : ui.borderSubtle,
              },
            ]}
            onPress={() => setUnreadOnly((prev) => !prev)}
          >
            <Text
              style={[
                styles.quickFilterText,
                { color: unreadOnly ? colors.foreground : colors.foreground },
              ]}
            >
              Unread
            </Text>
          </Pressable>
          <Pressable
            style={[
              styles.quickFilterChip,
              {
                backgroundColor: starredOnly ? ui.accentSoft : ui.surface,
                borderColor: starredOnly ? ui.accentMuted : ui.borderSubtle,
              },
            ]}
            onPress={() => setStarredOnly((prev) => !prev)}
          >
            <Text
              style={[
                styles.quickFilterText,
                { color: starredOnly ? colors.foreground : colors.foreground },
              ]}
            >
              Starred
            </Text>
          </Pressable>
          <Pressable
            style={[
              styles.quickFilterChip,
              {
                backgroundColor: hasAttachment ? ui.accentSoft : ui.surface,
                borderColor: hasAttachment ? ui.accentMuted : ui.borderSubtle,
              },
            ]}
            onPress={() => setHasAttachment((prev) => !prev)}
          >
            <Text
              style={[
                styles.quickFilterText,
                { color: hasAttachment ? colors.foreground : colors.foreground },
              ]}
            >
              Attachment
            </Text>
          </Pressable>
        </ScrollView>
      </View>

      {activeFilterCount > 0 && (
        <View style={styles.activeFiltersWrap}>
          <View
            style={[
              styles.activeFiltersCard,
              {
                backgroundColor: ui.surface,
                borderColor: ui.borderSubtle,
              },
            ]}
          >
            <Text style={[styles.activeFiltersText, { color: colors.mutedForeground }]}>
              {activeFilterSummary}
            </Text>
            <Pressable onPress={clearAllFilters}>
              <Text style={[styles.clearFiltersText, { color: ui.accent }]}>Clear all</Text>
            </Pressable>
          </View>
        </View>
      )}

      {/* Results */}
      <View style={styles.results}>
        {!canSearch ? (
          <View
            style={[
              styles.infoCard,
              {
                backgroundColor: ui.surface,
                borderColor: ui.borderSubtle,
              },
            ]}
          >
            <Text style={[styles.hintText, { color: colors.mutedForeground }]}>
              Search by sender, subject, or message text. You can also start with a filter if you
              are narrowing inbox triage.
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
              <View
                style={[
                  styles.infoCard,
                  {
                    backgroundColor: ui.surface,
                    borderColor: ui.borderSubtle,
                  },
                ]}
              >
                <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
                  {debouncedQuery.trim().length > 0
                    ? `No results matched "${debouncedQuery.trim()}". Try a broader phrase or clear a filter.`
                    : 'No results matched the current filters. Clear filters or switch folders.'}
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
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 14,
    height: 44,
  },
  searchInput: {
    flex: 1,
    fontSize: 14,
    lineHeight: 18,
    letterSpacing: -0.12,
    padding: 0,
  },
  cancelButton: {
    height: 38,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cancelText: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: -0.08,
  },
  results: {
    flex: 1,
  },
  activeFiltersWrap: {
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  activeFiltersCard: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
    paddingHorizontal: 12,
    paddingVertical: 9,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  activeFiltersText: {
    flex: 1,
    fontSize: 11,
    lineHeight: 15,
    letterSpacing: -0.06,
  },
  clearFiltersText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: -0.06,
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
    borderRadius: 999,
    paddingHorizontal: 13,
    paddingVertical: 8,
  },
  filterChipText: {
    fontSize: 11,
    lineHeight: 13,
    fontWeight: '600',
    letterSpacing: -0.06,
  },
  quickFilterChip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 999,
    paddingHorizontal: 13,
    paddingVertical: 8,
  },
  quickFilterText: {
    fontSize: 11,
    lineHeight: 13,
    fontWeight: '600',
    letterSpacing: -0.06,
  },
  infoCard: {
    marginHorizontal: 16,
    marginTop: 18,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 38,
    paddingHorizontal: 22,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 24,
  },
  hintText: {
    fontSize: 13,
    lineHeight: 18,
    letterSpacing: -0.08,
    textAlign: 'center',
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 48,
  },
  emptyText: {
    fontSize: 13,
    lineHeight: 18,
    letterSpacing: -0.08,
    textAlign: 'center',
  },
});
