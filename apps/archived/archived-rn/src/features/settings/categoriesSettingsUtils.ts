export type CategorySetting = {
  id: string;
  name: string;
  searchValue: string;
  order: number;
  isDefault?: boolean;
};

export function sortCategoriesByOrder(categories: CategorySetting[]): CategorySetting[] {
  return [...categories].sort((a, b) => a.order - b.order);
}

export function hasExactlyOneDefault(categories: CategorySetting[]): boolean {
  return categories.filter((category) => category.isDefault).length === 1;
}

export function applyDefaultCategory(
  categories: CategorySetting[],
  categoryId: string,
): CategorySetting[] {
  return categories.map((category) => ({
    ...category,
    isDefault: category.id === categoryId,
  }));
}

export function normalizeCategoryOrders(categories: CategorySetting[]): CategorySetting[] {
  return categories.map((category, index) => ({ ...category, order: index }));
}

export function deleteCategoryAndNormalize(
  categories: CategorySetting[],
  categoryId: string,
): CategorySetting[] {
  const remaining = categories.filter((category) => category.id !== categoryId);
  if (remaining.length === 0) {
    return categories;
  }

  if (!remaining.some((category) => category.isDefault)) {
    remaining[0] = { ...remaining[0], isDefault: true };
  }

  return normalizeCategoryOrders(remaining);
}

export function moveCategoryAndNormalize(
  categories: CategorySetting[],
  index: number,
  direction: 'up' | 'down',
): CategorySetting[] {
  const target = direction === 'up' ? index - 1 : index + 1;
  if (target < 0 || target >= categories.length) {
    return categories;
  }

  const next = [...categories];
  [next[index], next[target]] = [next[target], next[index]];
  return normalizeCategoryOrders(next);
}

export function resetFromDefaults(defaults: CategorySetting[]): CategorySetting[] {
  const ordered = normalizeCategoryOrders(defaults);
  if (ordered.length === 0 || ordered.some((category) => category.isDefault)) {
    return ordered;
  }
  ordered[0] = { ...ordered[0], isDefault: true };
  return ordered;
}
