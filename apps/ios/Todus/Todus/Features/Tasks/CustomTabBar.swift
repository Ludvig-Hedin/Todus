import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    var hasUpcomingCalendarEvent: Bool
    var onAI: () -> Void
    var onCreate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Tabs Pill
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Group {
                            if selectedTab == tab {
                                tab.activeIcon
                            } else if tab == .calendar {
                                tab.inactiveIcon(hasEvent: hasUpcomingCalendarEvent)
                            } else {
                                tab.inactiveIcon()
                            }
                        }
                        .frame(height: 42)
                        .padding(.horizontal, 14)
                        .foregroundStyle(selectedTab == tab ? .primary : AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.cardBorder)
            }

            // Actions Pill
            HStack(spacing: 0) {
                Button {
                    onAI()
                } label: {
                    Image(systemName: "sparkles")
                        .frame(height: 42)
                        .padding(.horizontal, 14)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)

                Button {
                    onCreate()
                } label: {
                    Image(systemName: "plus")
                        .frame(height: 42)
                        .padding(.horizontal, 14)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.cardBorder)
            }
        }
    }
}
