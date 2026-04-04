import SwiftUI

/// Dropdown menu for switching calendar view modes.
/// Sits inside AppTopHeader next to the title. Shows the current mode
/// and opens a menu to select another mode.
struct CalendarViewModePicker: View {
    @Binding var selection: CalendarViewMode
    var multiDayCount: Int = 3

    var body: some View {
        Menu {
            ForEach(CalendarViewMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = mode
                    }
                } label: {
                    Label {
                        Text(mode.menuLabel(multiDayCount: multiDayCount))
                    } icon: {
                        if mode == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.menuLabel(multiDayCount: multiDayCount))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }
}
