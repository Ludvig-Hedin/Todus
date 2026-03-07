import {
  applyDefaultCategory,
  deleteCategoryAndNormalize,
  hasExactlyOneDefault,
  moveCategoryAndNormalize,
  resetFromDefaults,
  sortCategoriesByOrder,
  type CategorySetting,
} from '../../../src/features/settings/categoriesSettingsUtils';
import {
  SettingsButton,
  SettingsCard,
  SettingsDescription,
  SettingsFieldLabel,
  SettingsScreenContainer,
  SettingsSectionTitle,
  SettingsTextInput,
} from '../../../src/features/settings/SettingsUI';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useEffect, useMemo, useState } from 'react';

export default function CategoriesSettings() {
  const { colors } = useTheme();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const settingsQuery = useQuery(trpc.settings.get.queryOptions());
  const defaultsQuery = useQuery(trpc.categories.defaults.queryOptions());
  const [categories, setCategories] = useState<CategorySetting[]>([]);
  const [isDirty, setIsDirty] = useState(false);

  const saveMutation = useMutation({
    ...trpc.settings.save.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() });
      setIsDirty(false);
    },
  });

  useEffect(() => {
    const saved = settingsQuery.data?.settings?.categories ?? [];
    const ordered = sortCategoriesByOrder(saved);
    setCategories(ordered);
    setIsDirty(false);
  }, [settingsQuery.data?.settings?.categories]);

  const hasDefault = useMemo(() => hasExactlyOneDefault(categories), [categories]);

  const updateCategory = (id: string, update: Partial<CategorySetting>) => {
    setCategories((current) =>
      current.map((category) => (category.id === id ? { ...category, ...update } : category)),
    );
    setIsDirty(true);
  };

  const setDefaultCategory = (id: string) => {
    setCategories((current) => applyDefaultCategory(current, id));
    setIsDirty(true);
  };

  const deleteCategory = (id: string) => {
    setCategories((current) => deleteCategoryAndNormalize(current, id));
    setIsDirty(true);
  };

  const addCategory = () => {
    setCategories((current) => [
      ...current,
      {
        id: `custom-${Date.now()}`,
        name: 'New Category',
        searchValue: '',
        order: current.length,
        isDefault: false,
      },
    ]);
    setIsDirty(true);
  };

  const moveCategory = (index: number, direction: 'up' | 'down') => {
    setCategories((current) => moveCategoryAndNormalize(current, index, direction));
    setIsDirty(true);
  };

  const saveChanges = async () => {
    if (!hasDefault) {
      Alert.alert('Validation error', 'Exactly one category must be marked as default.');
      return;
    }
    try {
      await saveMutation.mutateAsync({ categories });
      Alert.alert('Saved', 'Categories were updated.');
    } catch (error: any) {
      Alert.alert('Save failed', error?.message || 'Could not save categories.');
    }
  };

  const resetDefaults = async () => {
    const defaults = defaultsQuery.data;
    if (!defaults || defaults.length === 0) return;
    setCategories(resetFromDefaults(defaults));
    setIsDirty(true);
  };

  if (settingsQuery.isLoading) {
    return (
      <View style={[styles.loading, { backgroundColor: colors.background }]}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  return (
    <SettingsScreenContainer>
      <SettingsCard>
        <SettingsSectionTitle>Category Tabs</SettingsSectionTitle>
        <SettingsDescription>
          Configure tab names, label filters, ordering, and default selection for inbox categories.
        </SettingsDescription>
        <SettingsButton label="Add Category" onPress={addCategory} variant="secondary" />
        {categories.map((category, index) => (
          <View key={category.id} style={[styles.categoryCard, { borderColor: colors.border }]}>
            <SettingsFieldLabel>ID</SettingsFieldLabel>
            <Text style={[styles.idText, { color: colors.mutedForeground }]}>{category.id}</Text>

            <SettingsFieldLabel>Name</SettingsFieldLabel>
            <SettingsTextInput
              value={category.name}
              onChangeText={(value) => updateCategory(category.id, { name: value })}
            />

            <SettingsFieldLabel>Label Filters (comma-separated label IDs)</SettingsFieldLabel>
            <SettingsTextInput
              value={category.searchValue}
              onChangeText={(value) => updateCategory(category.id, { searchValue: value })}
              placeholder="IMPORTANT,UNREAD"
            />

            <View style={styles.row}>
              <View style={styles.defaultRow}>
                <Switch
                  value={!!category.isDefault}
                  onValueChange={() => setDefaultCategory(category.id)}
                />
                <Text style={[styles.rowLabel, { color: colors.foreground }]}>Default</Text>
              </View>
              <View style={styles.actions}>
                <Pressable
                  style={[styles.smallAction, { borderColor: colors.border }]}
                  onPress={() => moveCategory(index, 'up')}
                >
                  <Text style={{ color: colors.foreground }}>Up</Text>
                </Pressable>
                <Pressable
                  style={[styles.smallAction, { borderColor: colors.border }]}
                  onPress={() => moveCategory(index, 'down')}
                >
                  <Text style={{ color: colors.foreground }}>Down</Text>
                </Pressable>
                <Pressable
                  style={[styles.smallAction, { borderColor: colors.destructive }]}
                  onPress={() => deleteCategory(category.id)}
                >
                  <Text style={{ color: colors.destructive }}>Delete</Text>
                </Pressable>
              </View>
            </View>
          </View>
        ))}
      </SettingsCard>

      <View style={styles.footerActions}>
        <SettingsButton label="Reset to Defaults" onPress={resetDefaults} variant="secondary" />
        <SettingsButton
          label={saveMutation.isPending ? 'Saving...' : 'Save Changes'}
          onPress={saveChanges}
          disabled={saveMutation.isPending || !isDirty}
        />
      </View>
    </SettingsScreenContainer>
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  categoryCard: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    padding: 12,
    gap: 8,
  },
  idText: {
    fontSize: 12,
    marginBottom: 2,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  rowLabel: {
    fontSize: 14,
    fontWeight: '500',
  },
  defaultRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  smallAction: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  footerActions: {
    gap: 10,
  },
});
