import SwiftUI
import SwiftData

struct GmailOnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    
    @State private var isConnecting = false
    
    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Icon circle with envelope.badge image
                ZStack {
                    Circle()
                        .fill(AppTheme.surfacePrimary)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    
                    Image(systemName: "envelope.badge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundColor(AppTheme.accent)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gmail icon")
                
                // Title
                Text("Connect Gmail")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                // Subtitle
                Text("Grant access to your Gmail so Todus can fetch your emails. You can change this later in Settings.")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button {
                        isConnecting = true
                        Task {
                            await services.authService.signInWithGoogle()
                            if services.authService.isAuthenticated {
                                services.hasConfiguredGmailPrompt = true
                            }
                            isConnecting = false
                        }
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding(14)
                        } else {
                            Text("Connect Gmail")
                                .frame(maxWidth: .infinity)
                                .padding(14)
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isConnecting)
                    .accessibilityHint("Connect your Gmail account")
                    
                    Button {
                        services.hasConfiguredGmailPrompt = true
                    } label: {
                        Text("Skip for now")
                            .foregroundColor(AppTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Skip connecting Gmail for now")
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(.vertical, 32)
        }
    }
}
