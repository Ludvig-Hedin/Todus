import { Outlet } from 'react-router';
import { CrispWidget } from '@/components/shared/crisp-widget';

export default function FullWidthLayout() {
  return (
    <>
      <CrispWidget />
      <Outlet />
    </>
  );
}
