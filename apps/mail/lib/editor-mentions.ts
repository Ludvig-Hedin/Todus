import Mention from '@tiptap/extension-mention';
import { Extension, mergeAttributes } from '@tiptap/core';
import type { Editor, JSONContent, Range } from '@tiptap/react';
import Suggestion, { type SuggestionKeyDownProps, type SuggestionProps } from '@tiptap/suggestion';
import type { EditorCommandSurface, MentionKind, MentionRef } from '@zero/shared';

type SuggestionMenuItem = {
  id: string;
  title: string;
  subtitle?: string | null;
  badge?: string;
  group: string;
  keywords?: string[];
};

type SuggestionMenuConfig<T extends SuggestionMenuItem> = {
  emptyText: string;
  onSelect: (item: T, props: SuggestionProps<T>) => void;
};

type SlashCommandDefinition = SuggestionMenuItem & {
  run: (context: { editor: Editor; range: Range; surface: EditorCommandSurface }) => void;
};

type SlashCommandCallbacks = {
  onTemplateCommand?: () => void;
  onSignatureCommand?: () => void;
};

type MentionSuggestionItem = MentionRef &
  SuggestionMenuItem & {
    label: string;
  };

const mentionGroupLabels: Record<MentionKind, string> = {
  task: 'Tasks',
  thread: 'Email Threads',
  event: 'Events',
  person: 'People',
};

const parseScopedMentionQuery = (
  query: string,
  availableKinds?: MentionKind[],
): { query: string; kinds?: MentionKind[] } => {
  const scopedMatch = query.match(/^(task|thread|event|person):(.*)$/i);
  if (!scopedMatch) {
    return { query, kinds: availableKinds };
  }

  const scopedKind = scopedMatch[1].toLowerCase() as MentionKind;
  const normalizedKinds = availableKinds?.includes(scopedKind) ? [scopedKind] : availableKinds;

  return {
    query: scopedMatch[2]?.trimStart() ?? '',
    kinds: normalizedKinds,
  };
};

const ensurePopupRoot = () => {
  const root = document.createElement('div');
  root.className = 'editor-suggestion-menu';
  root.setAttribute('role', 'listbox');
  root.setAttribute('aria-label', 'Editor suggestions');

  return root;
};

const positionPopup = (
  popup: HTMLDivElement,
  props: Pick<SuggestionProps<SuggestionMenuItem>, 'clientRect'>,
) => {
  const rect = props.clientRect?.();
  if (!rect) {
    return;
  }

  popup.style.position = 'fixed';
  popup.style.left = `${rect.left}px`;
  popup.style.top = `${rect.bottom + 8}px`;
  popup.style.zIndex = '100000';
};

const createSuggestionRenderer = <T extends SuggestionMenuItem>({
  emptyText,
  onSelect,
}: SuggestionMenuConfig<T>) => {
  return () => {
    let popup: HTMLDivElement | null = null;
    let selectedIndex = 0;
    let latestProps: SuggestionProps<T> | null = null;

    const destroyPopup = () => {
      popup?.remove();
      popup = null;
      latestProps = null;
      selectedIndex = 0;
    };

    const selectItem = (index: number) => {
      const props = latestProps;
      if (!props) {
        return;
      }

      const item = props.items[index];
      if (!item) {
        return;
      }

      onSelect(item, props);
    };

    const renderPopup = () => {
      const props = latestProps;
      if (!popup || !props) {
        return;
      }

      popup.replaceChildren();
      popup.setAttribute('data-count', String(props.items.length));

      if (props.items.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'editor-suggestion-empty';
        empty.textContent = emptyText;
        popup.appendChild(empty);
        positionPopup(popup, props);
        return;
      }

      let previousGroup = '';

      props.items.forEach((item, index) => {
        if (item.group !== previousGroup) {
          const groupLabel = document.createElement('div');
          groupLabel.className = 'editor-suggestion-group';
          groupLabel.textContent = item.group;
          popup?.appendChild(groupLabel);
          previousGroup = item.group;
        }

        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'editor-suggestion-item';
        button.setAttribute('role', 'option');
        button.dataset.active = index === selectedIndex ? 'true' : 'false';

        const textColumn = document.createElement('span');
        textColumn.className = 'editor-suggestion-text';

        const title = document.createElement('span');
        title.className = 'editor-suggestion-title';
        title.textContent = item.title;
        textColumn.appendChild(title);

        if (item.subtitle) {
          const subtitle = document.createElement('span');
          subtitle.className = 'editor-suggestion-subtitle';
          subtitle.textContent = item.subtitle;
          textColumn.appendChild(subtitle);
        }

        button.appendChild(textColumn);

        if (item.badge) {
          const badge = document.createElement('span');
          badge.className = 'editor-suggestion-badge';
          badge.textContent = item.badge;
          button.appendChild(badge);
        }

        button.addEventListener('mousedown', (event) => {
          event.preventDefault();
          selectItem(index);
        });

        popup?.appendChild(button);
      });

      positionPopup(popup, props);
      popup
        .querySelector<HTMLElement>('[data-active="true"]')
        ?.scrollIntoView({ block: 'nearest' });
    };

    const moveSelection = (direction: 1 | -1) => {
      const props = latestProps;
      if (!props?.items.length) {
        return;
      }

      selectedIndex = (selectedIndex + direction + props.items.length) % props.items.length;
      renderPopup();
    };

    return {
      onStart: (props: SuggestionProps<T>) => {
        latestProps = props;
        popup = ensurePopupRoot();
        document.body.appendChild(popup);
        selectedIndex = 0;
        renderPopup();
      },
      onUpdate: (props: SuggestionProps<T>) => {
        latestProps = props;
        selectedIndex = Math.min(selectedIndex, Math.max(props.items.length - 1, 0));
        renderPopup();
      },
      onKeyDown: (props: SuggestionKeyDownProps) => {
        if (props.event.key === 'ArrowDown') {
          moveSelection(1);
          return true;
        }

        if (props.event.key === 'ArrowUp') {
          moveSelection(-1);
          return true;
        }

        if (props.event.key === 'Enter') {
          selectItem(selectedIndex);
          return true;
        }

        if (props.event.key === 'Escape') {
          destroyPopup();
          return true;
        }

        return false;
      },
      onExit: () => {
        destroyPopup();
      },
    };
  };
};

const insertMentionTrigger = (editor: Editor, range: Range, kind?: MentionKind) => {
  editor
    .chain()
    .focus()
    .deleteRange(range)
    .insertContent(kind ? `@${kind}:` : '@')
    .run();
};

const formatMentionLabel = (mention: MentionRef) => `@${mention.displayText || mention.title}`;

export const MentionChip = Mention.extend({
  name: 'mentionChip',

  addAttributes() {
    return {
      ...this.parent?.(),
      kind: { default: 'task' },
      title: { default: '' },
      subtitle: { default: null },
      displayText: { default: '' },
      accessibilityLabel: { default: '' },
    };
  },

  renderText({ node }) {
    return formatMentionLabel(node.attrs as MentionRef);
  },

  renderHTML({ node, HTMLAttributes }) {
    return [
      'span',
      mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, {
        'data-mention-chip': 'true',
        'data-mention-kind': node.attrs.kind,
        'data-mention-id': node.attrs.id,
        'data-mention-display-text': node.attrs.displayText,
        'aria-label': node.attrs.accessibilityLabel,
      }),
      formatMentionLabel(node.attrs as MentionRef),
    ];
  },
});

export const createMentionExtension = ({
  searchMentions,
  availableKinds,
}: {
  searchMentions: (query: string, kinds?: MentionKind[]) => Promise<MentionRef[]>;
  availableKinds?: MentionKind[];
}) =>
  MentionChip.configure({
    deleteTriggerWithBackspace: true,
    HTMLAttributes: {
      class: 'mention-chip',
    },
    suggestion: {
      char: '@',
      items: async ({ query }) => {
        const scopedQuery = parseScopedMentionQuery(query, availableKinds);
        const mentions = await searchMentions(scopedQuery.query, scopedQuery.kinds);

        return mentions.map(
          (mention) =>
            ({
              ...mention,
              label: mention.displayText,
              badge: mention.kind,
              group: mentionGroupLabels[mention.kind],
            }) satisfies MentionSuggestionItem,
        );
      },
      render: createSuggestionRenderer<MentionSuggestionItem>({
        emptyText: 'No mentions found',
        onSelect: (item, props) => {
          props.command({
            ...item,
            label: item.displayText,
          });
        },
      }),
      command: ({ editor, range, props }) => {
        const mentionProps = props as MentionSuggestionItem;

        editor
          .chain()
          .focus()
          .insertContentAt(range, [
            {
              type: 'mentionChip',
              attrs: {
                ...mentionProps,
                label: mentionProps.displayText,
              },
            },
            {
              type: 'text',
              text: ' ',
            },
          ])
          .run();
      },
    },
  });

const commandMatchesQuery = (command: SlashCommandDefinition, query: string) => {
  const normalizedQuery = query.trim().toLowerCase();
  if (!normalizedQuery) {
    return true;
  }

  return [command.title, command.subtitle ?? '', command.group, ...(command.keywords ?? [])].some(
    (value) => value.toLowerCase().includes(normalizedQuery),
  );
};

const baseSlashCommands = (
  surface: EditorCommandSurface,
  callbacks: SlashCommandCallbacks,
): SlashCommandDefinition[] => {
  const formatting: SlashCommandDefinition[] = [
    {
      id: 'paragraph',
      title: 'Paragraph',
      subtitle: 'Continue with plain text',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['text', 'paragraph'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).setParagraph().run();
      },
    },
    {
      id: 'heading-1',
      title: 'Heading 1',
      subtitle: 'Large section heading',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['title', 'h1'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).setHeading({ level: 1 }).run();
      },
    },
    {
      id: 'heading-2',
      title: 'Heading 2',
      subtitle: 'Medium section heading',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['subtitle', 'h2'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).setHeading({ level: 2 }).run();
      },
    },
    {
      id: 'heading-3',
      title: 'Heading 3',
      subtitle: 'Small section heading',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['subtitle', 'h3'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).setHeading({ level: 3 }).run();
      },
    },
    {
      id: 'bullet-list',
      title: 'Bullet List',
      subtitle: 'Create an unordered list',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['list', 'unordered'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).toggleBulletList().run();
      },
    },
    {
      id: 'ordered-list',
      title: 'Numbered List',
      subtitle: 'Create an ordered list',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['list', 'ordered', 'numbered'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).toggleOrderedList().run();
      },
    },
    {
      id: 'checklist',
      title: 'Checklist',
      subtitle: 'Track items with checkboxes',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['task list', 'checkbox'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).toggleTaskList().run();
      },
    },
    {
      id: 'divider',
      title: 'Divider',
      subtitle: 'Insert a section divider',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['separator', 'rule'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).setHorizontalRule().run();
      },
    },
    {
      id: 'quote',
      title: 'Quote',
      subtitle: 'Insert a quoted block',
      badge: 'Format',
      group: 'Formatting',
      keywords: ['blockquote'],
      run: ({ editor, range }) => {
        editor.chain().focus().deleteRange(range).toggleBlockquote().run();
      },
    },
  ];

  const references: SlashCommandDefinition[] = [
    {
      id: 'task-reference',
      title: 'Task Mention',
      subtitle: 'Search and insert a task reference',
      badge: 'Reference',
      group: 'Insert Reference',
      keywords: ['task', 'todo'],
      run: ({ editor, range }) => insertMentionTrigger(editor, range, 'task'),
    },
    {
      id: 'thread-reference',
      title: 'Email Thread',
      subtitle: 'Search and insert an email thread reference',
      badge: 'Reference',
      group: 'Insert Reference',
      keywords: ['email', 'thread', 'mail'],
      run: ({ editor, range }) => insertMentionTrigger(editor, range, 'thread'),
    },
    {
      id: 'person-reference',
      title: 'Person',
      subtitle: 'Search and insert a person reference',
      badge: 'Reference',
      group: 'Insert Reference',
      keywords: ['person', 'contact'],
      run: ({ editor, range }) => insertMentionTrigger(editor, range, 'person'),
    },
  ];

  const composeHelpers: SlashCommandDefinition[] =
    surface === 'email-compose'
      ? [
          {
            id: 'template',
            title: 'Template',
            subtitle: 'Open saved email templates',
            badge: 'Compose',
            group: 'Compose Helpers',
            keywords: ['snippet', 'saved'],
            run: ({ editor, range }) => {
              editor.chain().focus().deleteRange(range).run();
              callbacks.onTemplateCommand?.();
            },
          },
          {
            id: 'signature',
            title: 'Signature',
            subtitle: 'Toggle your email signature',
            badge: 'Compose',
            group: 'Compose Helpers',
            keywords: ['footer', 'signoff'],
            run: ({ editor, range }) => {
              editor.chain().focus().deleteRange(range).run();
              callbacks.onSignatureCommand?.();
            },
          },
        ]
      : [];

  return surface === 'ai-chat'
    ? [...references, ...formatting]
    : [...formatting, ...references, ...composeHelpers];
};

export const createSlashCommandExtension = (
  surface: EditorCommandSurface,
  callbacks: SlashCommandCallbacks = {},
) =>
  Extension.create({
    name: `slashCommands-${surface}`,
    addProseMirrorPlugins() {
      const commands = baseSlashCommands(surface, callbacks);

      return [
        Suggestion<SlashCommandDefinition>({
          editor: this.editor,
          char: '/',
          allowSpaces: false,
          items: ({ query }) => commands.filter((command) => commandMatchesQuery(command, query)),
          render: createSuggestionRenderer<SlashCommandDefinition>({
            emptyText: 'No commands found',
            onSelect: (item, props) => {
              item.run({ editor: props.editor, range: props.range, surface });
            },
          }),
          command: ({ editor, range, props }) => {
            props.run({ editor, range, surface });
          },
        }),
      ];
    },
  });

export const extractMentionRefsFromDoc = (content: JSONContent | Record<string, unknown> | null) => {
  const mentions: MentionRef[] = [];

  const visit = (node: JSONContent | Record<string, unknown> | null | undefined) => {
    if (!node || typeof node !== 'object') {
      return;
    }

    const record = node as JSONContent & { attrs?: Record<string, unknown> };
    if (record.type === 'mentionChip' && record.attrs) {
      mentions.push({
        id: String(record.attrs.id ?? ''),
        kind: String(record.attrs.kind ?? 'task') as MentionKind,
        title: String(record.attrs.title ?? record.attrs.label ?? ''),
        subtitle:
          record.attrs.subtitle === null || record.attrs.subtitle === undefined
            ? null
            : String(record.attrs.subtitle),
        displayText: String(record.attrs.displayText ?? record.attrs.label ?? record.attrs.title ?? ''),
        accessibilityLabel: String(
          record.attrs.accessibilityLabel ??
            `Mention ${record.attrs.displayText ?? record.attrs.label ?? record.attrs.title ?? ''}`,
        ),
      });
    }

    if (Array.isArray(record.content)) {
      record.content.forEach((child) => visit(child));
    }
  };

  visit(content as JSONContent | null);

  return mentions.filter((mention) => mention.id && mention.displayText);
};

export const sanitizeMentionHtml = (html: string) => {
  if (typeof DOMParser === 'undefined') {
    return html;
  }

  const doc = new DOMParser().parseFromString(html, 'text/html');
  doc.querySelectorAll('[data-mention-chip="true"]').forEach((element) => {
    const text = element.textContent ?? '';
    element.replaceWith(doc.createTextNode(text));
  });

  return doc.body.innerHTML;
};
