import SwiftUI
import AppKit


/// macOS sign-in screen — adapted from the iOS AuthView.
/// Stage 1: Email input + social sign-in buttons (Apple, Google).
/// Stage 2: 6-digit OTP code entry with resend + auto-submit.
struct MacAuthView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    private var authService: AuthService { services.authService }

    @State private var email = ""
    @State private var code = ""
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isCodeFocused: Bool

    /// Blue accent used for primary action buttons (matches iOS app)
    private let accentBlue = Color(red: 0.25, green: 0.48, blue: 1.0)

    private let expectedCodeLength = 6

    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Brand logo + title
            VStack(spacing: 4) {
                Image("BrandLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .padding(.bottom, 6)

                Text("Welcome to Todus")
                    .font(.system(size: 24, weight: .semibold))

                Text("Your AI agent for emails")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.5))

                Text(otpPendingEmail == nil ? "Sign in to get started" : "Enter the code sent to your email")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.4))
            }

            Spacer()

            // Auth content — switches between email input and OTP verification
            VStack(spacing: 12) {
                // Error banner
                if let error = authService.lastErrorMessage {
                    errorBanner(error)
                }

                if let pendingEmail = otpPendingEmail {
                    otpVerificationView(email: pendingEmail)
                } else {
                    emailInputView
                    socialButtons
                    footer
                }
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.25), value: otpPendingEmail)
        .animation(.snappy(duration: 0.3), value: authService.lastErrorMessage != nil)
    }

    /// Extracts the pending email if in OTP state
    private var otpPendingEmail: String? {
        if case .otpPending(let email) = authService.authState { return email }
        return nil
    }

    // MARK: - Email Input (Stage 1)

    private var emailInputView: some View {
        VStack(spacing: 10) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($isEmailFocused)
                .font(.system(size: 14, weight: .medium))
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.background)
                )
                .overlay(
                    Capsule()
                        .stroke(.separator, lineWidth: 1)
                )
                .focusEffectDisabled()
                .onSubmit {
                    guard isValidEmail else { return }
                    Task { await authService.sendEmailOTP(email: email) }
                }

            // Send code button — only visible when email looks valid
            if isValidEmail {
                Button {
                    Task { await authService.sendEmailOTP(email: email) }
                } label: {
                    Text("Send code")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(accentBlue, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .pointerStyle(.link)
                .disabled(authService.isLoading)
            }
        }
    }

    // MARK: - OTP Verification (Stage 2)

    private func otpVerificationView(email: String) -> some View {
        VStack(spacing: 10) {
            // Show the email we're verifying
            Text(email)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            // Code input — auto-submits when 6 digits entered
            TextField("Verification code", text: $code)
                .textContentType(.oneTimeCode)
                .focused($isCodeFocused)
                .font(.system(size: 14, weight: .medium))
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.background)
                )
                .overlay(
                    Capsule()
                        .stroke(.separator, lineWidth: 1)
                )
                .focusEffectDisabled()
                .onChange(of: code) { _, newValue in
                    if newValue.count >= expectedCodeLength {
                        Task { await authService.verifyEmailOTP(code: newValue) }
                    }
                }
                .onAppear {
                    isCodeFocused = true
                }

            // Show Verify when code is complete, Resend when not
            if code.count >= expectedCodeLength {
                Button {
                    Task { await authService.verifyEmailOTP(code: code) }
                } label: {
                    Text("Verify code")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(accentBlue, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .pointerStyle(.link)
                .disabled(authService.isLoading)
            } else {
                Button {
                    Task { await authService.sendEmailOTP(email: email) }
                } label: {
                    Text("Resend code")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(.background, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .pointerStyle(.link)
                .disabled(authService.isLoading)
            }

            // Open email app — uses mailto: which opens default macOS mail client
            Button {
                if let url = URL(string: "mailto:") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open Email App")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(.background, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.separator, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)

            // Back button — returns to main login screen
            Button {
                code = ""
                authService.returnToLogin()
            } label: {
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .padding(.top, 4)
        }
        .overlay {
            if authService.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        VStack(spacing: 10) {
            // Divider with "or"
            HStack(spacing: 12) {
                Rectangle().fill(.separator).frame(height: 0.5)
                Text("or")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Rectangle().fill(.separator).frame(height: 0.5)
            }
            .padding(.vertical, 6)

            // Apple Sign In
            Button {
                Task { await authService.signInWithApple() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 18, height: 18)
                    Text("Continue with Apple")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)

            // Google Sign In
            Button {
                Task { await authService.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleLogoView()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.background, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.separator, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
        }
        .disabled(authService.isLoading)
        .opacity(authService.isLoading ? 0.6 : 1)
        .overlay {
            if authService.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                authService.continueAsGuest()
            } label: {
                Text("Continue without account")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .padding(.top, 20)

            // Terms / Privacy links
            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://todus.app/terms") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Terms of Service")
                }
                .pointerStyle(.link)
                Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3)
                Button {
                    if let url = URL(string: "https://todus.app/privacy") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Privacy Policy")
                }
                .pointerStyle(.link)
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.7))
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .padding(.top, 28)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
            Spacer()
        }
        .padding(12)
        .background(
            Color.red.opacity(0.08),
            in: Capsule()
        )
    }
}

// MARK: - Google Logo

/// Pixel-accurate Google "G" logo — paths converted 1:1 from the official Google SVG
/// (viewBox 0 0 24 24). Scaled proportionally to whatever frame is applied.
private struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Blue #4285F4
            var blue = Path()
            blue.move(to: pt(22.56, 12.25))
            blue.addCurve(to: pt(22.36, 10.00),
                          control1: pt(22.56, 11.47), control2: pt(22.49, 10.72))
            blue.addLine(to: pt(12.00, 10.00))
            blue.addLine(to: pt(12.00, 14.26))
            blue.addLine(to: pt(17.92, 14.26))
            blue.addCurve(to: pt(15.71, 17.57),
                          control1: pt(17.66, 15.63), control2: pt(16.88, 16.79))
            blue.addLine(to: pt(15.71, 20.34))
            blue.addLine(to: pt(19.28, 20.34))
            blue.addCurve(to: pt(22.56, 12.25),
                          control1: pt(21.36, 18.42), control2: pt(22.56, 15.60))
            blue.closeSubpath()
            context.fill(blue, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))

            // Green #34A853
            var green = Path()
            green.move(to: pt(12.00, 23.00))
            green.addCurve(to: pt(19.28, 20.34),
                           control1: pt(14.97, 23.00), control2: pt(17.46, 22.02))
            green.addLine(to: pt(15.71, 17.57))
            green.addCurve(to: pt(12.00, 18.63),
                           control1: pt(14.73, 18.23), control2: pt(13.48, 18.63))
            green.addCurve(to: pt(5.84, 14.10),
                           control1: pt(9.14, 18.63), control2: pt(6.71, 16.70))
            green.addLine(to: pt(2.18, 14.10))
            green.addLine(to: pt(2.18, 16.94))
            green.addCurve(to: pt(12.00, 23.00),
                           control1: pt(3.99, 20.53), control2: pt(7.70, 23.00))
            green.closeSubpath()
            context.fill(green, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))

            // Yellow #FBBC05
            var yellow = Path()
            yellow.move(to: pt(5.84, 14.09))
            yellow.addCurve(to: pt(5.49, 12.00),
                            control1: pt(5.62, 13.43), control2: pt(5.49, 12.73))
            yellow.addCurve(to: pt(5.84, 9.91),
                            control1: pt(5.49, 11.27), control2: pt(5.62, 10.57))
            yellow.addLine(to: pt(5.84, 7.07))
            yellow.addLine(to: pt(2.18, 7.07))
            yellow.addCurve(to: pt(1.00, 12.00),
                            control1: pt(1.43, 8.55), control2: pt(1.00, 10.22))
            yellow.addCurve(to: pt(2.18, 16.93),
                            control1: pt(1.00, 13.78), control2: pt(1.43, 15.45))
            yellow.addLine(to: pt(5.03, 14.71))
            yellow.addLine(to: pt(5.84, 14.09))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(red: 0.980, green: 0.737, blue: 0.020)))

            // Red #EA4335
            var red = Path()
            red.move(to: pt(12.00, 5.38))
            red.addCurve(to: pt(16.21, 7.02),
                         control1: pt(13.62, 5.38), control2: pt(15.06, 5.94))
            red.addLine(to: pt(19.36, 3.87))
            red.addCurve(to: pt(12.00, 1.00),
                         control1: pt(17.45, 2.09), control2: pt(14.97, 1.00))
            red.addCurve(to: pt(2.18, 7.07),
                         control1: pt(7.70, 1.00), control2: pt(3.99, 3.47))
            red.addLine(to: pt(5.84, 9.91))
            red.addCurve(to: pt(12.00, 5.38),
                         control1: pt(6.71, 7.31), control2: pt(9.14, 5.38))
            red.closeSubpath()
            context.fill(red, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))
        }
    }
}
