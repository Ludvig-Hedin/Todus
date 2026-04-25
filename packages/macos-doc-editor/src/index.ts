import { Editor } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';

/* Styles: editor.css loaded by index.html in bundle */

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        todusDoc?: { postMessage: (body: unknown) => void };
      };
    };
    todusEditor?: TodusEditorApi;
  }
}

export type TodusEditorApi = {
  setContent: (json: unknown) => void;
  getJSON: () => unknown;
  getText: () => string;
  setTheme: (mode: 'light' | 'dark') => void;
  run: (command: string) => void;
};

let editor: Editor | null = null;
let debounceTimer: ReturnType<typeof setTimeout> | null = null;
const DEBOUNCE_MS = 350;

function postToNative(message: Record<string, unknown>) {
  try {
    window.webkit?.messageHandlers?.todusDoc?.postMessage(message);
  } catch {
    /* no-op in browser */
  }
}

function notifyChange() {
  if (!editor) return;
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    if (!editor) return;
    const json = editor.getJSON();
    const text = editor.getText();
    postToNative({ type: 'change', content: json, contentText: text });
  }, DEBOUNCE_MS);
}

function mount() {
  const el = document.getElementById('editor');
  if (!el) return;

  editor = new Editor({
    element: el,
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
      }),
      TaskList,
      TaskItem.configure({ nested: true }),
    ],
    content: { type: 'doc', content: [{ type: 'paragraph' }] },
    editorProps: {
      attributes: {
        class: 'todus-prose',
      },
    },
    onUpdate: () => notifyChange(),
    onCreate: () => postToNative({ type: 'ready' }),
  });

  const api: TodusEditorApi = {
    setContent: (json: unknown) => {
      if (!editor) return;
      try {
        editor.commands.setContent(json as Parameters<Editor['commands']['setContent']>[0]);
        notifyChange();
      } catch {
        editor.commands.setContent('<p></p>');
      }
    },
    getJSON: () => editor?.getJSON() ?? { type: 'doc', content: [] },
    getText: () => editor?.getText() ?? '',
    setTheme: (mode) => {
      document.documentElement.classList.toggle('dark', mode === 'dark');
    },
    run: (command: string) => {
      if (!editor) return;
      const chain = editor.chain().focus();
      switch (command) {
        case 'bold':
          chain.toggleBold().run();
          break;
        case 'italic':
          chain.toggleItalic().run();
          break;
        case 'heading1':
          chain.toggleHeading({ level: 1 }).run();
          break;
        case 'heading2':
          chain.toggleHeading({ level: 2 }).run();
          break;
        case 'bulletList':
          chain.toggleBulletList().run();
          break;
        case 'orderedList':
          chain.toggleOrderedList().run();
          break;
        case 'taskList':
          chain.toggleTaskList().run();
          break;
        case 'paragraph':
          chain.setParagraph().run();
          break;
        case 'undo':
          chain.undo().run();
          break;
        case 'redo':
          chain.redo().run();
          break;
        default:
          break;
      }
      notifyChange();
    },
  };

  window.todusEditor = api;
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mount);
} else {
  mount();
}
