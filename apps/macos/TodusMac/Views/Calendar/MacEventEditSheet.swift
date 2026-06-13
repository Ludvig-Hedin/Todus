import SwiftUI
import SwiftData

/// Native in-app event create/edit sheet for the macOS calendar.
///
/// Replaces the previous "open in Calendar.app" delegation. Mirrors the iOS
/// `EKEventDetailSheet` capabilities but built with native SwiftUI controls
/// because macOS has no `EventKitUI`. Supports:
///   * Create or edit modes (toggled by `existingEvent`)
///   * Title, all-day toggle, start/end date pickers, location, notes
///   * Apple calendar (source) picker — gated by `source.isWritable`
///   * Folder picker for local Todus folder association
///   * Inline validation (end > start)
///   * Save / Delete (edit-only) / Cancel with confirmation + loading state
///   * Error alert on save/delete failure
struct MacEventEditSheet: View {
    enum Mode {
        case create(suggestedStart: Date)
        case edit(event: CalendarEvent)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(MacAppServices.self) private var services
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    let mode: Mode
    /// Optional callback invoked after a successful save/delete so the host
    /// view can refresh its event list immediately (rather than relying on
    /// EKEventStoreChanged round-trips).
    var onCompletion: (() -> Void)?

    // MARK: - Form state

    @State private var title: String = ""
    @State private var isAllDay: Bool = false
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedCalendarSourceId: String? = nil
    @State private var selectedFolderID: UUID? = nil

    // MARK: - UI state

    @State private var appleSources: [CalendarSource] = []
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String? = nil
    /// True when editing an event whose original calendar is no longer in the
    /// writable list (account removed/disabled). We surface a warning and
    /// require the user to actively pick a calendar before saving.
    @State private var originalCalendarMissing = false

    // MARK: - Derived

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var endIsBeforeStart: Bool {
        !isAllDay && endDate <= startDate
    }

    private var canSave: Bool {
        guard !trimmedTitle.isEmpty, !endIsBeforeStart, !isSaving, !isDeleting else {
            return false
        }
        // If the event's original calendar is gone, force a fresh pick before
        // enabling Save. selectedCalendarSourceId is nil until the user picks one.
        if originalCalendarMissing, selectedCalendarSourceId == nil {
            return false
        }
        return true
    }

    // Writable Apple calendars only. Backend Google CRUD isn't wired yet, so
    // we deliberately limit the picker to sources where `isWritable == true`.
    private var writableSources: [CalendarSource] {
        appleSources.filter(\.isWritable)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 460)
        .frame(minHeight: 520, idealHeight: 560)
        .background(MacTheme.contentBackground)
        .focusEffectDisabled()
        .task { await primeForm() }
        .alert(
            "Couldn't save event",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove the event from your calendar.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isEditing ? "calendar.badge.clock" : "calendar.badge.plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MacTheme.accent)
            Text(isEditing ? "Edit Event" : "New Event")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer()
            if isSaving || isDeleting {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacTheme.spacing16) {
                titleField
                allDayAndDates
                calendarPicker
                folderPicker
                locationField
                notesField
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Title")
            TextField("Add a title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
    }

    @ViewBuilder
    private var allDayAndDates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isAllDay.animation(MacTheme.Motion.fast)) {
                Text("All-day")
                    .font(.system(size: 13))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(MacTheme.switchTint)
            .onChange(of: isAllDay) { _, nowAllDay in
                applyAllDayBaseline(isAllDay: nowAllDay)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Starts")
                DatePicker(
                    "",
                    selection: $startDate,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: startDate) { _, newStart in
                    // Auto-bump end when the user moves start past the existing end.
                    // All-day uses inclusive day boundaries (end == start = single
                    // day); timed events get the original-or-1h duration.
                    if isAllDay {
                        let dayStart = Calendar.current.startOfDay(for: newStart)
                        if endDate < dayStart { endDate = dayStart }
                    } else if endDate <= newStart {
                        endDate = newStart.addingTimeInterval(3600)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Ends")
                DatePicker(
                    "",
                    selection: $endDate,
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                if endIsBeforeStart {
                    Label("End time must be after the start time.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Calendar")
            if originalCalendarMissing, selectedCalendarSourceId == nil {
                // Edit mode loaded an event whose calendar is no longer in the
                // writable-sources list (permission revoked, calendar removed,
                // etc.). Force the user to pick a different calendar before
                // Save will enable. Once they pick one, the warning hides
                // because the missing-calendar situation has been resolved
                // by the new selection.
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This event's calendar is no longer accessible. Pick a different calendar to save changes.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            if writableSources.isEmpty {
                Text("No writable calendars available.")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.mutedText)
            } else {
                // Real picker over writable Apple calendars. `performSave`
                // extracts the underlying `EKCalendar.calendarIdentifier` from
                // the composite source id and passes it to CalendarService so
                // the event lands on the chosen calendar (not just the system
                // default). Backend Google CRUD isn't wired, hence Apple-only.
                Picker("", selection: Binding<String?>(
                    get: { selectedCalendarSourceId ?? writableSources.first?.id },
                    set: { selectedCalendarSourceId = $0 }
                )) {
                    ForEach(writableSources) { source in
                        Text(source.displayName).tag(Optional(source.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text("Apple Calendar accounts only — Google Calendar editing coming soon.")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.mutedText)
            }
        }
    }

    @ViewBuilder
    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Folder")
            Picker("", selection: Binding<UUID?>(
                get: { selectedFolderID },
                set: { selectedFolderID = $0 }
            )) {
                Text("Unfiled").tag(UUID?.none)
                if !folders.isEmpty {
                    Divider()
                    ForEach(folders) { folder in
                        Text(folder.name).tag(Optional(folder.id))
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Location")
            TextField("Optional", text: $location)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Notes")
            TextEditor(text: $notes)
                .font(.system(size: 13))
                .frame(minHeight: 80, maxHeight: 140)
                .padding(6)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isEditing {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || isDeleting)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving || isDeleting)

            Button(isEditing ? "Save" : "Create") {
                Task { await performSave() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary)
            .textCase(.uppercase)
    }

    /// Normalises the start/end dates whenever the user toggles the all-day
    /// switch. Idempotent — bails out early if the dates are already on the
    /// expected baseline so re-toggling doesn't snap times the user just set.
    private func applyAllDayBaseline(isAllDay: Bool) {
        let cal = Calendar.current
        if isAllDay {
            let dayStart = cal.startOfDay(for: startDate)
            // `endDate` here is the INCLUSIVE last day (the seed subtracts a day
            // and `performSave` adds it back). A single-day all-day event must
            // therefore have end == start; using +86400 produced a 2-day event
            // once `performSave` bumped it again.
            let expectedEnd = dayStart
            // Avoid stomping user-set values that already match the baseline.
            if startDate == dayStart && endDate == expectedEnd { return }
            startDate = dayStart
            endDate = expectedEnd
        } else {
            // 9:00 AM on the start day, end +1h. If already on that baseline, skip.
            guard let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: startDate) else { return }
            let expectedEnd = nineAM.addingTimeInterval(3600)
            if startDate == nineAM && endDate == expectedEnd { return }
            startDate = nineAM
            endDate = expectedEnd
        }
    }

    // MARK: - Lifecycle

    /// Pre-fills the form from `mode` and asks the calendar service for the
    /// list of writable Apple sources. Runs once on appear.
    private func primeForm() async {
        // 1. Pull writable Apple sources for the calendar picker.
        let sources = await services.calendarService.listAppleSources()
        appleSources = sources

        // 2. Seed form values based on mode.
        switch mode {
        case .create(let suggestedStart):
            title = ""
            isAllDay = false
            startDate = suggestedStart
            endDate = suggestedStart.addingTimeInterval(3600)
            location = ""
            notes = ""
            selectedFolderID = nil
            // Default calendar selection: respect user's saved default for Apple
            // if it's still writable, else fall back to the system primary, else
            // first writable source.
            selectedCalendarSourceId = resolveDefaultSourceId(in: sources)

        case .edit(let event):
            title = event.title
            isAllDay = event.isAllDay
            startDate = event.startDate
            // EventKit stores all-day end as midnight of the next day; show the
            // user the inclusive day they actually picked.
            if event.isAllDay {
                endDate = Calendar.current.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
            } else {
                endDate = event.endDate
            }
            location = ""        // EKEvent.location/notes aren't on CalendarEvent yet; left blank to avoid wiping on save.
            notes = ""           // updateEvent only patches fields we pass, so leaving these blank is safe.
            selectedFolderID = event.folderID
            // Match the existing event's calendar in the picker. The picker stays
            // editable in edit mode so the user can move the event to another
            // calendar — and MUST, when the original calendar is missing (below).
            if let calId = event.calendarIdentifier {
                let composite = "\(CalendarSourceIDPrefix.apple):\(calId)"
                if let match = sources.first(where: { $0.id == composite })?.id {
                    selectedCalendarSourceId = match
                } else if sources.contains(where: { $0.isWritable }) {
                    // Original calendar is gone from the list (account removed/
                    // disabled) but writable calendars exist. Flag it + leave the
                    // selection nil so `canSave` forces the user to actively pick
                    // a calendar instead of silently saving the edit to a default
                    // they didn't choose. Activates the existing
                    // `originalCalendarMissing` guard, which was dead because
                    // nothing ever set it true.
                    originalCalendarMissing = true
                    selectedCalendarSourceId = nil
                } else {
                    // No writable calendars at all — the picker's "No writable
                    // calendars available" notice already covers this; don't
                    // double-warn.
                    selectedCalendarSourceId = nil
                }
            } else {
                selectedCalendarSourceId = resolveDefaultSourceId(in: sources)
            }
        }
    }

    private func resolveDefaultSourceId(in sources: [CalendarSource]) -> String? {
        let writable = sources.filter(\.isWritable)
        let prefs = services.calendarPreferences
        if let preferred = prefs.defaultId(forAccountKey: CalendarSourceIDPrefix.apple),
           writable.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if let primary = writable.first(where: { $0.isPrimary }) {
            return primary.id
        }
        return writable.first?.id
    }

    /// Strips the `apple:` prefix off a composite source id and returns the
    /// underlying `EKCalendar.calendarIdentifier`. Returns nil for non-Apple
    /// (e.g. Google) sources so callers can fall back to the default calendar.
    private func extractAppleCalendarIdentifier(from sourceId: String?) -> String? {
        let prefix = "\(CalendarSourceIDPrefix.apple):"
        guard let sid = sourceId, sid.hasPrefix(prefix) else { return nil }
        return String(sid.dropFirst(prefix.count))
    }

    // MARK: - Save / Delete

    @MainActor
    private func performSave() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        // EventKit treats all-day end-date inclusively at midnight of the next
        // day. Bump it by 24h on save so a single-day all-day event spans the
        // whole displayed day.
        let resolvedEnd: Date = {
            guard isAllDay else { return endDate }
            return Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }()

        let appleCalendarId = extractAppleCalendarIdentifier(from: selectedCalendarSourceId)

        do {
            switch mode {
            case .create:
                try await services.calendarService.createEvent(
                    title: trimmedTitle,
                    startDate: startDate,
                    endDate: resolvedEnd,
                    folderID: selectedFolderID,
                    calendarIdentifier: appleCalendarId
                )
            case .edit(let event):
                try await services.calendarService.updateEvent(
                    identifier: event.id,
                    title: trimmedTitle,
                    startDate: startDate,
                    endDate: resolvedEnd,
                    notes: notes.isEmpty ? nil : notes,
                    calendarIdentifier: appleCalendarId
                )
                // Folder mapping lives in CalendarService's UserDefaults map.
                await services.calendarService.setFolderID(selectedFolderID, for: event.id)
            }
            onCompletion?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performDelete() async {
        guard case .edit(let event) = mode else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.calendarService.deleteEvent(identifier: event.id)
            onCompletion?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
