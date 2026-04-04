'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { useConnections } from '@/hooks/use-connections';

interface ConnectionFilterContextType {
  /** Set of connection IDs currently visible in the unified view */
  enabledConnectionIds: Set<string>;
  /** Toggle a single connection's visibility */
  toggleConnection: (id: string) => void;
  /** Enable all connections */
  enableAll: () => void;
  /** Whether more than one connection is enabled (unified mode) */
  isUnifiedView: boolean;
  /** Whether all connections are enabled */
  isAllEnabled: boolean;
  /** Total number of connections available */
  totalConnections: number;
}

const ConnectionFilterContext = createContext<ConnectionFilterContextType | null>(null);

const STORAGE_KEY = 'todus:enabled-connection-ids';

export function ConnectionFilterProvider({ children }: { children: React.ReactNode }) {
  const { data } = useConnections();
  const allConnectionIds = useMemo(
    () => data?.connections.map((c) => c.id) ?? [],
    [data?.connections],
  );

  const [enabledConnectionIds, setEnabledConnectionIds] = useState<Set<string>>(() => {
    if (typeof window === 'undefined') return new Set<string>();
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) return new Set(JSON.parse(stored) as string[]);
    } catch {}
    return new Set<string>();
  });

  // When connections load for the first time or new ones are added, enable them by default
  useEffect(() => {
    if (allConnectionIds.length === 0) return;
    setEnabledConnectionIds((prev) => {
      // If no stored state, enable all
      if (prev.size === 0) return new Set(allConnectionIds);
      // If new connections appeared, add them as enabled
      const updated = new Set(prev);
      let changed = false;
      for (const id of allConnectionIds) {
        if (!updated.has(id)) {
          updated.add(id);
          changed = true;
        }
      }
      // Remove connections that no longer exist
      for (const id of updated) {
        if (!allConnectionIds.includes(id)) {
          updated.delete(id);
          changed = true;
        }
      }
      return changed ? updated : prev;
    });
  }, [allConnectionIds]);

  // Persist to localStorage
  useEffect(() => {
    if (enabledConnectionIds.size === 0) return;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify([...enabledConnectionIds]));
    } catch {}
  }, [enabledConnectionIds]);

  const toggleConnection = useCallback(
    (id: string) => {
      setEnabledConnectionIds((prev) => {
        const next = new Set(prev);
        if (next.has(id)) {
          // Don't allow disabling the last connection
          if (next.size <= 1) return prev;
          next.delete(id);
        } else {
          next.add(id);
        }
        return next;
      });
    },
    [],
  );

  const enableAll = useCallback(() => {
    setEnabledConnectionIds(new Set(allConnectionIds));
  }, [allConnectionIds]);

  const isUnifiedView = enabledConnectionIds.size > 1;
  const isAllEnabled = allConnectionIds.length > 0 && allConnectionIds.every((id) => enabledConnectionIds.has(id));

  const value = useMemo(
    () => ({
      enabledConnectionIds,
      toggleConnection,
      enableAll,
      isUnifiedView,
      isAllEnabled,
      totalConnections: allConnectionIds.length,
    }),
    [enabledConnectionIds, toggleConnection, enableAll, isUnifiedView, isAllEnabled, allConnectionIds.length],
  );

  return (
    <ConnectionFilterContext.Provider value={value}>{children}</ConnectionFilterContext.Provider>
  );
}

export function useConnectionFilter() {
  const ctx = useContext(ConnectionFilterContext);
  if (!ctx) {
    throw new Error('useConnectionFilter must be used within ConnectionFilterProvider');
  }
  return ctx;
}
