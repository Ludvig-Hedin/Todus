import assert from 'node:assert/strict';
import test from 'node:test';
import { sortThreadNotes } from './notesUtils';

test('sortThreadNotes orders pinned notes first and then by order ascending', () => {
  const input = [
    { id: 'c', isPinned: false, order: 2 },
    { id: 'a', isPinned: true, order: 3 },
    { id: 'b', isPinned: true, order: 1 },
    { id: 'd', isPinned: false, order: 1 },
  ];

  const sorted = sortThreadNotes(input);
  assert.deepEqual(
    sorted.map((note) => note.id),
    ['b', 'a', 'd', 'c'],
  );
});

test('sortThreadNotes handles missing order values as 0', () => {
  const input = [
    { id: 'a', isPinned: false },
    { id: 'b', isPinned: false, order: 2 },
    { id: 'c', isPinned: false, order: 1 },
  ];

  const sorted = sortThreadNotes(input);
  assert.deepEqual(
    sorted.map((note) => note.id),
    ['a', 'c', 'b'],
  );
});
