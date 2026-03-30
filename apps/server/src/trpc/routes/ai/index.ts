import { listConversations, getConversation, saveConversation, deleteConversation } from './conversations';
import { compose, generateEmailSubject } from './compose';
import { generateSearchQuery } from './search';
import { transcribeAudio } from './transcribeAudio';
import { webSearch } from './webSearch';
import { router } from '../../trpc';

export const aiRouter = router({
  generateSearchQuery,
  compose,
  generateEmailSubject,
  webSearch,
  transcribeAudio,
  listConversations,
  getConversation,
  saveConversation,
  deleteConversation,
});
