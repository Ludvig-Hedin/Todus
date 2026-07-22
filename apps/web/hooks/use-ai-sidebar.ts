import { useCallback, useEffect, useState } from 'react';
import { useQueryState } from 'nuqs';

export type AssistantDisplayMode = 'sidebar' | 'full' | 'floating' | 'window';

type ViewMode = 'sidebar' | 'popup' | 'fullscreen';

const DISPLAY_MODE_KEY = 'mail.ai.displayMode';

const isValidDisplayMode = (value: string | null): value is AssistantDisplayMode =>
  value === 'sidebar' || value === 'full' || value === 'floating' || value === 'window';

export function useAIFullScreen() {
  const [isFullScreenQuery, setIsFullScreenQuery] = useQueryState('isFullScreen');
  const [isFullScreen, setIsFullScreenState] = useState<boolean>(() => {
    if (isFullScreenQuery) return isFullScreenQuery === 'true';
    if (typeof window === 'undefined') return false;
    return localStorage.getItem('ai-fullscreen') === 'true';
  });

  const setIsFullScreen = useCallback(
    (value: boolean) => {
      setIsFullScreenState(value);
      if (!value) {
        if (typeof window !== 'undefined') localStorage.removeItem('ai-fullscreen');
        setTimeout(() => {
          void setIsFullScreenQuery(null);
        }, 0);
        return;
      }

      void setIsFullScreenQuery('true');
      if (typeof window !== 'undefined') localStorage.setItem('ai-fullscreen', 'true');
    },
    [setIsFullScreenQuery],
  );

  useEffect(() => {
    const queryValue = isFullScreenQuery === 'true';
    if (isFullScreenQuery !== null && queryValue !== isFullScreen) {
      setIsFullScreenState(queryValue);
    }
  }, [isFullScreenQuery, isFullScreen]);

  useEffect(() => {
    if (typeof window !== 'undefined' && !isFullScreenQuery) {
      if (localStorage.getItem('ai-fullscreen') === 'true') {
        void setIsFullScreenQuery('true');
      }
    }
    if (isFullScreenQuery === null && isFullScreen) setIsFullScreenState(false);
  }, [isFullScreenQuery, setIsFullScreenQuery, isFullScreen]);

  return { isFullScreen, setIsFullScreen };
}

export function useAssistantDisplayMode(setIsFullScreen: (value: boolean) => void) {
  const [displayMode, setDisplayModeState] = useState<AssistantDisplayMode>(() => {
    if (typeof window === 'undefined') return 'sidebar';
    const stored = window.localStorage.getItem(DISPLAY_MODE_KEY);
    return isValidDisplayMode(stored) ? stored : 'sidebar';
  });

  const setDisplayMode = useCallback(
    (mode: AssistantDisplayMode) => {
      setDisplayModeState(mode);
      if (typeof window !== 'undefined') window.localStorage.setItem(DISPLAY_MODE_KEY, mode);
      setIsFullScreen(mode === 'full');
    },
    [setIsFullScreen],
  );

  return { displayMode, setDisplayMode };
}

export function useAISidebar() {
  const [open, setOpenQuery] = useQueryState('aiSidebar');
  const [viewModeQuery, setViewModeQuery] = useQueryState('viewMode');
  const { isFullScreen, setIsFullScreen } = useAIFullScreen();
  const [viewMode, setViewModeState] = useState<ViewMode>(() => {
    if (viewModeQuery) return viewModeQuery as ViewMode;
    if (typeof window !== 'undefined') {
      const savedViewMode = localStorage.getItem('ai-viewmode');
      if (savedViewMode === 'sidebar' || savedViewMode === 'popup') return savedViewMode;
    }
    return 'popup';
  });

  const setViewMode = useCallback(
    (mode: ViewMode) => {
      setViewModeState(mode);
      void setViewModeQuery(mode === 'popup' ? null : mode);
      if (typeof window !== 'undefined') localStorage.setItem('ai-viewmode', mode);
    },
    [setViewModeQuery],
  );

  const setOpen = useCallback(
    (openState: boolean) => {
      if (!openState) {
        if (typeof window !== 'undefined') localStorage.removeItem('ai-sidebar-open');
        setTimeout(() => {
          void setOpenQuery(null);
        }, 0);
        return;
      }

      void setOpenQuery('true');
      if (typeof window !== 'undefined') localStorage.setItem('ai-sidebar-open', 'true');
    },
    [setOpenQuery],
  );

  const toggleOpen = useCallback(() => setOpen(open !== 'true'), [open, setOpen]);

  useEffect(() => {
    if (viewModeQuery && viewModeQuery !== viewMode) {
      setViewModeState(viewModeQuery as ViewMode);
    }
  }, [viewModeQuery, viewMode]);

  return {
    open: open === 'true',
    viewMode,
    setViewMode,
    setOpen,
    toggleOpen,
    toggleViewMode: () => setViewMode(viewMode === 'popup' ? 'sidebar' : 'popup'),
    isFullScreen,
    setIsFullScreen,
    isSidebar: viewMode === 'sidebar',
    isPopup: viewMode === 'popup',
  };
}
