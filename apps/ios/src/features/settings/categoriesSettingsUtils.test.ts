import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyDefaultCategory,
  deleteCategoryAndNormalize,
  hasExactlyOneDefault,
  moveCategoryAndNormalize,
  normalizeCategoryOrders,
  resetFromDefaults,
  sortCategoriesByOrder,
  type CategorySetting,
} from './categoriesSettingsUtils';

const fixture = (): CategorySetting[] => [
  { id: 'primary', name: 'Primary', searchValue: 'INBOX', order: 2, isDefault: false },
  { id: 'updates', name: 'Updates', searchValue: 'CATEGORY_UPDATES', order: 1, isDefault: true },
  { id: 'promo', name: 'Promotions', searchValue: 'CATEGORY_PROMOTIONS', order: 0, isDefault: false },
];

test('sortCategoriesByOrder sorts by order ascending', () => {
  const sorted = sortCategoriesByOrder(fixture());
  assert.deepEqual(
    sorted.map((category) => category.id),
    ['promo', 'updates', 'primary'],
  );
});

test('hasExactlyOneDefault validates default count', () => {
  assert.equal(hasExactlyOneDefault(fixture()), true);
  assert.equal(
    hasExactlyOneDefault([
      { id: 'a', name: 'A', searchValue: '', order: 0, isDefault: false },
      { id: 'b', name: 'B', searchValue: '', order: 1, isDefault: false },
    ]),
    false,
  );
});

test('applyDefaultCategory sets only one default', () => {
  const next = applyDefaultCategory(fixture(), 'primary');
  assert.equal(next.find((category) => category.id === 'primary')?.isDefault, true);
  assert.equal(next.find((category) => category.id === 'updates')?.isDefault, false);
});

test('deleteCategoryAndNormalize removes category, normalizes order, and backfills default', () => {
  const next = deleteCategoryAndNormalize(fixture(), 'updates');
  assert.deepEqual(
    next.map((category) => category.id),
    ['primary', 'promo'],
  );
  assert.deepEqual(
    next.map((category) => category.order),
    [0, 1],
  );
  assert.equal(next[0].isDefault, true);
});

test('moveCategoryAndNormalize swaps category order when move is valid', () => {
  const ordered = normalizeCategoryOrders(sortCategoriesByOrder(fixture()));
  const next = moveCategoryAndNormalize(ordered, 1, 'up');
  assert.deepEqual(
    next.map((category) => category.id),
    ['updates', 'promo', 'primary'],
  );
  assert.deepEqual(
    next.map((category) => category.order),
    [0, 1, 2],
  );
});

test('resetFromDefaults normalizes order and ensures a default exists', () => {
  const defaults: CategorySetting[] = [
    { id: 'work', name: 'Work', searchValue: 'WORK', order: 3 },
    { id: 'personal', name: 'Personal', searchValue: 'PERSONAL', order: 8 },
  ];
  const next = resetFromDefaults(defaults);
  assert.deepEqual(
    next.map((category) => category.order),
    [0, 1],
  );
  assert.equal(next[0].isDefault, true);
});
