import SwiftUI
import UIKit

struct AuthPageView: View {
    @Environment(AppServices.self) private var services

    @State private var email = ""
    @State private var code = ""

    @FocusState private var isInputFocused: Bool

    // OTP codes from Supabase are always 6 digits
    private let expectedCodeLength = 6

    // Email validation — checks basic RFC 5322 format
    private var isValidEmail: Bool {
        let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }

    // Code is valid once user has typed the full expected number of digits
    private var isValidCode: Bool {
        code.count == expectedCodeLength
    }

    // Opens the user's email inbox — tries known app-specific inbox URL schemes
    // before falling back to mailto: (which opens the composer, not the inbox).
    private func openEmailInbox() {
        // Ordered by most-specific inbox URL first.
        // googlegmail:/// opens Gmail directly to the inbox (not the composer).
        // ms-outlook://inbox opens Outlook inbox.
        // message:// opens Apple Mail (may land in inbox).
        let inboxSchemes = [
            "googlegmail:///",
            "ms-outlook://inbox",
            "readdle-spark://",
            "message://"
        ]

        for scheme in inboxSchemes {
            if let url = URL(string: scheme),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }

        // Last resort: mailto: will open whatever the default email app is,
        // but unfortunately lands on the compose screen on most clients.
        if let url = URL(string: "mailto:") {
            UIApplication.shared.open(url)
        }
    }

    // Triggers OTP verification — extracted so it can be called from button and onChange
    private func verifyCode() {
        Task {
            await services.authStore.verifyMagicLinkCode(code)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()
                .onTapGesture {
                    isInputFocused = false
                    dismissKeyboard()
                }

            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 24)

                Text(services.authStore.pendingEmail == nil ? "Login" : "Enter code")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)

                VStack(spacing: 10) {

                    if let pendingEmail = services.authStore.pendingEmail {
                        Text(pendingEmail)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("Verification code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.2)
                            .focused($isInputFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                            // Auto-submit as soon as the user types the 6th digit — no button tap needed
                            .onChange(of: code) { _, newValue in
                                if newValue.count == expectedCodeLength {
                                    verifyCode()
                                }
                            }

                        Button(action: verifyCode) {
                            Text("Verify code")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        // Disabled until the user has typed all expected digits
                        .disabled(!isValidCode)
                        .opacity(isValidCode ? 1 : 0.4)

                        // Opens the user's email inbox directly (not the compose screen).
                        // Uses app-specific URL schemes tried in priority order — see openEmailInbox().
                        Button(action: openEmailInbox) {
                            Label("Open Email App", systemImage: "envelope.open")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(AppSecondaryButtonStyle())

                        Button("Use another email") {
                            code = ""
                            services.authStore.returnToLogin()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    } else {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)  // Enables iOS autofill suggestions for saved emails
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.2)
                            .focused($isInputFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )

                        // Only show send button when email is valid (non-empty and valid format)
                        if isValidEmail {
                            Button {
                                Task {
                                    await services.authStore.sendMagicLink(email: email)
                                }
                            } label: {
                                Text("Send magic link")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(AppPrimaryButtonStyle())
                        }

                        Button("Continue as guest") {
                            services.authStore.continueAsGuest()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                }

                // Error messages styled distinctly so they're not missed
                if let message = services.authStore.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)

            .task {
                try? await Task.sleep(for: .milliseconds(200))
                isInputFocused = true
            }
        }
    }
}
