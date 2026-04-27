import { HotkeyProviderWrapper } from '@/components/providers/hotkey-provider-wrapper';
import { CommandPaletteProvider } from '@/components/context/command-palette-context';
import { OfflineIndicator } from '~/components/offline-indicator';

import { Outlet } from 'react-router';


export default function Layout() {
  return (
    <CommandPaletteProvider>
      <HotkeyProviderWrapper>
        <div className="flex flex-col max-h-screen w-full">
          <OfflineIndicator />
          <div className="relative flex flex-1 overflow-hidden">
            <Outlet />
          </div>
        </div>
      </HotkeyProviderWrapper>
    </CommandPaletteProvider>
  );
}
