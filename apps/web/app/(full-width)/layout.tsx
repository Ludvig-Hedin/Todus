import { SmoothScrollProvider } from '@/components/providers/smooth-scroll';
import { CrispWidget } from '@/components/shared/crisp-widget';
import { Outlet } from 'react-router';

export default function FullWidthLayout() {
  return (
    <SmoothScrollProvider>
      <CrispWidget />
      <Outlet />
    </SmoothScrollProvider>
  );
}
