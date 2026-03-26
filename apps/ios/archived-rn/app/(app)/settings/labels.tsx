/**
 * Labels settings — full CRUD for custom labels with color selection.
 */
import {
  ScrollView,
  StyleSheet,
  Text,
  View,
  ActivityIndicator,
  Pressable,
  Alert,
} from 'react-native';
import { SettingsButton, SettingsTextInput } from '../../../src/features/settings/SettingsUI';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Check, Tag, Plus, Pencil, Trash2 } from 'lucide-react-native';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { typography } from '@zero/design-tokens';
import { useMemo, useState } from 'react';

const LABEL_COLORS = [
  { textColor: '#FFFFFF', backgroundColor: '#202020' },
  { textColor: '#D1F0D9', backgroundColor: '#12341D' },
  { textColor: '#FDECCE', backgroundColor: '#413111' },
  { textColor: '#FDD9DF', backgroundColor: '#411D23' },
  { textColor: '#D8E6FD', backgroundColor: '#1C2A41' },
  { textColor: '#E8DEFD', backgroundColor: '#2C2341' },
] as const;

type LabelColor = (typeof LABEL_COLORS)[number];

export default function LabelsSettings() {
  const { colors, ui } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery(trpc.labels.list.queryOptions());
  const createLabelMutation = useMutation(trpc.labels.create.mutationOptions());
  const updateLabelMutation = useMutation(trpc.labels.update.mutationOptions());
  const deleteLabelMutation = useMutation(trpc.labels.delete.mutationOptions());

  const labels = (data as any[]) ?? [];
  const [editingLabelId, setEditingLabelId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [selectedColor, setSelectedColor] = useState<LabelColor>(LABEL_COLORS[0]);

  const editingLabel = useMemo(
    () => labels.find((label: any) => label.id === editingLabelId) ?? null,
    [labels, editingLabelId],
  );

  const openCreate = () => {
    setEditingLabelId(null);
    setName('');
    setSelectedColor(LABEL_COLORS[0]);
  };

  const openEdit = (label: any) => {
    setEditingLabelId(label.id);
    setName(label.name);
    const colorMatch =
      LABEL_COLORS.find(
        (color) =>
          color.backgroundColor === label.color?.backgroundColor &&
          color.textColor === label.color?.textColor,
      ) ?? LABEL_COLORS[0];
    setSelectedColor(colorMatch);
  };

  const refreshLabels = () => {
    queryClient.invalidateQueries({ queryKey: trpc.labels.list.queryKey() });
  };

  const saveLabel = async () => {
    if (!name.trim()) {
      Alert.alert('Validation error', 'Label name is required.');
      return;
    }
    try {
      if (editingLabel) {
        await updateLabelMutation.mutateAsync({
          id: editingLabel.id,
          name: name.trim(),
          color: selectedColor,
        });
      } else {
        await createLabelMutation.mutateAsync({
          name: name.trim(),
          color: selectedColor,
        });
      }
      refreshLabels();
      openCreate();
    } catch (error: any) {
      Alert.alert('Save failed', error?.message || 'Could not save label.');
    }
  };

  const deleteLabel = (labelId: string) => {
    Alert.alert(
      'Delete label?',
      'This action cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteLabelMutation.mutateAsync({ id: labelId });
              refreshLabels();
              if (editingLabelId === labelId) {
                openCreate();
              }
            } catch (error: any) {
              Alert.alert('Delete failed', error?.message || 'Could not delete label.');
            }
          },
        },
      ],
      { cancelable: true },
    );
  };

  return (
    <View style={[styles.container, { backgroundColor: ui.canvas }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
        <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Labels</Text>

        <View
          style={[
            styles.editor,
            { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
          ]}
        >
          <View style={styles.editorHeader}>
            <Text style={[styles.editorTitle, { color: colors.foreground }]}>
              {editingLabel ? 'Edit Label' : 'Create Label'}
            </Text>
            <Pressable
              style={[
                styles.actionButton,
                { borderColor: ui.borderStrong, backgroundColor: ui.surface },
              ]}
              onPress={openCreate}
            >
              <Plus size={16} color={colors.foreground} />
            </Pressable>
          </View>
          <SettingsTextInput value={name} onChangeText={setName} placeholder="Label name" />
          <View style={styles.colorRow}>
            {LABEL_COLORS.map((color) => {
              const selected =
                selectedColor.backgroundColor === color.backgroundColor &&
                selectedColor.textColor === color.textColor;
              return (
                <Pressable
                  key={color.backgroundColor}
                  style={[
                    styles.colorChip,
                    {
                      backgroundColor: color.backgroundColor,
                      borderColor: selected ? colors.foreground : ui.borderStrong,
                    },
                  ]}
                  onPress={() => setSelectedColor(color)}
                >
                  {selected ? (
                    <View style={[styles.colorChipBadge, { backgroundColor: colors.foreground }]}>
                      <Check size={10} color={colors.background} />
                    </View>
                  ) : null}
                </Pressable>
              );
            })}
          </View>
          <SettingsButton
            label={
              createLabelMutation.isPending || updateLabelMutation.isPending
                ? 'Saving...'
                : editingLabel
                  ? 'Save Changes'
                  : 'Create Label'
            }
            onPress={saveLabel}
            disabled={createLabelMutation.isPending || updateLabelMutation.isPending}
          />
        </View>

        {isLoading ? (
          <ActivityIndicator color={colors.foreground} style={{ marginVertical: 24 }} />
        ) : labels.length === 0 ? (
          <View
            style={[
              styles.emptyState,
              { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
            ]}
          >
            <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
              No custom labels yet.
            </Text>
          </View>
        ) : (
          <View
            style={[
              styles.section,
              { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
            ]}
          >
            {labels.map((label: any, index: number) => (
              <View
                key={label.id || index}
                style={[
                  styles.labelItem,
                  index < labels.length - 1 && {
                    borderBottomWidth: StyleSheet.hairlineWidth,
                    borderBottomColor: ui.borderSubtle,
                  },
                ]}
              >
                <View style={styles.labelLeft}>
                  <Tag size={18} color={label.color?.textColor || colors.mutedForeground} />
                  <Text
                    style={[
                      styles.labelName,
                      {
                        color: label.color?.textColor || colors.foreground,
                        backgroundColor: label.color?.backgroundColor || 'transparent',
                      },
                    ]}
                  >
                    {label.name || 'Unnamed'}
                  </Text>
                </View>
                <View style={styles.labelActions}>
                  <Pressable
                    style={[
                      styles.actionButton,
                      { borderColor: ui.borderStrong, backgroundColor: ui.surface },
                    ]}
                    onPress={() => openEdit(label)}
                  >
                    <Pencil size={14} color={colors.foreground} />
                  </Pressable>
                  <Pressable
                    style={[
                      styles.actionButton,
                      { borderColor: ui.borderStrong, backgroundColor: ui.surface },
                    ]}
                    onPress={() => deleteLabel(label.id)}
                  >
                    <Trash2 size={14} color={colors.destructive} />
                  </Pressable>
                </View>
              </View>
            ))}
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: 16 },
  sectionTitle: {
    fontSize: typography.size.sm,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
  },
  section: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  editor: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 12,
    gap: 10,
    marginBottom: 12,
  },
  editorHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  editorTitle: {
    fontSize: typography.size.md,
    fontWeight: '600',
  },
  colorRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  colorChip: {
    width: 30,
    height: 30,
    borderRadius: 15,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  colorChipBadge: {
    width: 18,
    height: 18,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
  },
  labelItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    gap: 12,
  },
  labelLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flex: 1,
  },
  labelName: {
    fontSize: typography.size.sm,
    fontWeight: '600',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
  },
  labelActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  actionButton: {
    borderWidth: StyleSheet.hairlineWidth,
    width: 28,
    height: 28,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyState: {
    padding: 24,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
  },
  emptyText: { fontSize: typography.size.sm },
});
