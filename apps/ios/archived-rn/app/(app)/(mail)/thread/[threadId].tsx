/**
 * Thread detail screen — stacked detail route used on narrow layouts.
 */
import { ThreadDetailPane } from '../../../../src/features/mail/ThreadDetailPane';
import { useLocalSearchParams, useRouter } from 'expo-router';

export default function ThreadDetailScreen() {
  const { threadId } = useLocalSearchParams<{ threadId: string }>();
  const router = useRouter();
  return <ThreadDetailPane threadId={threadId} showBackButton onBackPress={() => router.back()} />;
}
