/**
 * Shared state for undo-send banner and compose restore payload.
 */
import { atom } from 'jotai';

export type UndoComposePayload = {
  to: string;
  cc: string;
  bcc: string;
  subject: string;
  message: string;
  attachments: {
    name: string;
    type: string;
    size: number;
    lastModified: number;
    base64: string;
  }[];
};

export type PendingUndoSend = {
  messageId: string;
  sendAt: number;
  wasUserScheduled: boolean;
  payload?: UndoComposePayload;
};

export const pendingUndoSendAtom = atom<PendingUndoSend | null>(null);
export const undoComposePrefillAtom = atom<UndoComposePayload | null>(null);
