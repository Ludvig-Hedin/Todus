/**
 * Create/edit a calendar event. Pure logic lives in
 * `@/lib/calendar-event-form`; this is the form shell.
 *
 * Create mode now exposes a calendar picker (workstream A2) so events can be
 * created on a chosen writable calendar instead of always defaulting to
 * `primary`. The picker is parent-controlled: the page owns the selected
 * `calendarId` (it threads it into the create payload) and passes the writable
 * calendar list in. When no list is supplied the picker is hidden and behavior
 * falls back to the parent's default calendar (backward compatible).
 */
import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Trash2, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import {
  type EventFormValues,
  bumpEndAfterStart,
  validateForm,
} from '@/lib/calendar-event-form';

export type EventDialogMode = 'create' | 'edit';

/** Minimal calendar shape the picker needs (subset of `calendar.calendars`). */
export interface EventDialogCalendar {
  id: string;
  name: string;
  color: string;
  primary: boolean;
  /** owner/writer = writable; reader/freeBusyReader = read-only. */
  accessRole: string;
}

interface EventEditDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mode: EventDialogMode;
  initialValues: EventFormValues;
  readOnly?: boolean;
  saving?: boolean;
  deleting?: boolean;
  onSave: (values: EventFormValues) => void;
  onDelete?: () => void;
  /**
   * Calendars selectable in create mode. Read-only calendars are filtered out
   * here (you can't create events on them). Omit to hide the picker.
   * TODO(PAR-A2): switch the source query to `calendarsMulti` once the server
   * exposes it so events can be created across multiple connected accounts.
   */
  calendars?: EventDialogCalendar[];
  /** Currently selected target calendar id (create mode). */
  calendarId?: string;
  /** Called when the user picks a different target calendar (create mode). */
  onCalendarChange?: (calendarId: string) => void;
}

export function EventEditDialog({
  open,
  onOpenChange,
  mode,
  initialValues,
  readOnly = false,
  saving = false,
  deleting = false,
  onSave,
  onDelete,
  calendars,
  calendarId,
  onCalendarChange,
}: EventEditDialogProps) {
  const [values, setValues] = useState<EventFormValues>(initialValues);

  // Only writable calendars can host new events. Show the picker only in
  // create mode, when not read-only, and when there's a real choice to make.
  const writableCalendars = (calendars ?? []).filter(
    (c) => c.accessRole === 'owner' || c.accessRole === 'writer',
  );
  const showCalendarPicker =
    mode === 'create' &&
    !readOnly &&
    !!onCalendarChange &&
    writableCalendars.length > 1;

  // Reset the form whenever the dialog (re)opens with new initial values.
  useEffect(() => {
    if (open) setValues(initialValues);
  }, [open, initialValues]);

  const set = <K extends keyof EventFormValues>(key: K, value: EventFormValues[K]) =>
    setValues((prev) => ({ ...prev, [key]: value }));

  const handleStartChange = (key: 'startDate' | 'startTime', value: string) => {
    setValues((prev) => bumpEndAfterStart({ ...prev, [key]: value }));
  };

  const handleSave = () => {
    const error = validateForm(values);
    if (error) {
      toast.error(error);
      return;
    }
    onSave(values);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle className="text-[15px]">
            {mode === 'create' ? 'New event' : readOnly ? 'Event' : 'Edit event'}
          </DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-3 py-1">
          <Input
            autoFocus={!readOnly}
            disabled={readOnly}
            value={values.title}
            onChange={(e) => set('title', e.target.value)}
            placeholder="Add a title"
            aria-label="Event title"
          />

          {showCalendarPicker && (
            <div className="flex flex-col gap-1">
              <Label htmlFor="calendar-picker" className="text-muted-foreground text-[11px]">
                Calendar
              </Label>
              <Select
                value={calendarId}
                onValueChange={(value) => onCalendarChange?.(value)}
              >
                <SelectTrigger id="calendar-picker" aria-label="Calendar">
                  <SelectValue placeholder="Select a calendar" />
                </SelectTrigger>
                <SelectContent>
                  {writableCalendars.map((cal) => (
                    <SelectItem key={cal.id} value={cal.id}>
                      <span className="flex items-center gap-2">
                        <span
                          className="h-2.5 w-2.5 shrink-0 rounded-[3px]"
                          style={{ backgroundColor: cal.color }}
                          aria-hidden
                        />
                        <span className="truncate">{cal.name}</span>
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="flex items-center justify-between">
            <Label htmlFor="all-day" className="text-[13px]">
              All day
            </Label>
            <Switch
              id="all-day"
              disabled={readOnly}
              checked={values.allDay}
              onCheckedChange={(checked) =>
                setValues((prev) => bumpEndAfterStart({ ...prev, allDay: checked }))
              }
            />
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Starts</Label>
              <Input
                type="date"
                disabled={readOnly}
                value={values.startDate}
                onChange={(e) => handleStartChange('startDate', e.target.value)}
                aria-label="Start date"
              />
              {!values.allDay && (
                <Input
                  type="time"
                  disabled={readOnly}
                  value={values.startTime}
                  onChange={(e) => handleStartChange('startTime', e.target.value)}
                  aria-label="Start time"
                />
              )}
            </div>
            <div className="flex flex-col gap-1">
              <Label className="text-muted-foreground text-[11px]">Ends</Label>
              <Input
                type="date"
                disabled={readOnly}
                value={values.endDate}
                onChange={(e) => set('endDate', e.target.value)}
                aria-label="End date"
              />
              {!values.allDay && (
                <Input
                  type="time"
                  disabled={readOnly}
                  value={values.endTime}
                  onChange={(e) => set('endTime', e.target.value)}
                  aria-label="End time"
                />
              )}
            </div>
          </div>

          <Input
            disabled={readOnly}
            value={values.location}
            onChange={(e) => set('location', e.target.value)}
            placeholder="Location (optional)"
            aria-label="Location"
          />
          <Textarea
            disabled={readOnly}
            value={values.description}
            onChange={(e) => set('description', e.target.value)}
            placeholder="Notes (optional)"
            rows={3}
            aria-label="Notes"
          />
        </div>

        <DialogFooter className="flex items-center justify-between gap-2 sm:justify-between">
          {mode === 'edit' && onDelete && !readOnly ? (
            <Button
              variant="ghost"
              size="sm"
              className="text-destructive hover:text-destructive"
              onClick={onDelete}
              disabled={deleting || saving}
              aria-label="Delete event"
            >
              {deleting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Trash2 className="h-4 w-4" />}
            </Button>
          ) : (
            <span />
          )}
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
              {readOnly ? 'Close' : 'Cancel'}
            </Button>
            {!readOnly && (
              <Button size="sm" onClick={handleSave} disabled={saving || deleting}>
                {saving ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : mode === 'create' ? (
                  'Create'
                ) : (
                  'Save'
                )}
              </Button>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
