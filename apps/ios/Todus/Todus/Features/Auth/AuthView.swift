import SwiftUI

/// Sign-in screen — matches the RN app's auth flow.
/// Stage 1: Email input + social buttons (Apple, Google).
/// Stage 2: 6-digit OTP code entry with resend + auto-submit.
struct AuthView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    private var authService: AuthService { services.authService }

    @State private var email = ""
    @State private var code = ""
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isCodeFocused: Bool

    /// Blue accent used for primary action buttons (matches todo app)
    private let accentBlue = Color(red: 0.25, green: 0.48, blue: 1.0)

    private let expectedCodeLength = 6

    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Brand logo + title — compact spacing to match RN app
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
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.5))

                    Text(otpPendingEmail == nil ? "Sign in to get started" : "Enter the code sent to your email")
                        .font(.system(size: 14, weight: .regular))
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
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        // Dismiss keyboard on tap outside any input field
        .onTapGesture {
            isEmailFocused = false
            isCodeFocused = false
        }
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
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.continue)
                .focused($isEmailFocused)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceSecondary, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.strongBorder, lineWidth: 1)
                )
                .onSubmit {
                    guard isValidEmail else { return }
                    isEmailFocused = false
                    Task { await authService.sendEmailOTP(email: email) }
                }

            // Send code button — only visible when email looks valid
            if isValidEmail {
                Button {
                    isEmailFocused = false
                    Task { await authService.sendEmailOTP(email: email) }
                } label: {
                    Text("Send code")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accentBlue, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(authService.isLoading)
            }
        }
    }

    // MARK: - OTP Verification (Stage 2)

    private func otpVerificationView(email: String) -> some View {
        VStack(spacing: 10) {
            // Show the email we're verifying
            Text(email)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            // Code input — auto-submits when 6 digits entered
            TextField("Verification code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .submitLabel(.done)
                .focused($isCodeFocused)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceSecondary, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.strongBorder, lineWidth: 1)
                )
                .onChange(of: code) { _, newValue in
                    if newValue.count >= expectedCodeLength {
                        isCodeFocused = false
                        Task { await authService.verifyEmailOTP(code: newValue) }
                    }
                }
                .onAppear {
                    isCodeFocused = true
                }

            // Show Verify when code is complete, Resend when not
            if code.count >= expectedCodeLength {
                Button {
                    isCodeFocused = false
                    Task { await authService.verifyEmailOTP(code: code) }
                } label: {
                    Text("Verify code")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accentBlue, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(authService.isLoading)
            } else {
                Button {
                    Task { await authService.sendEmailOTP(email: email) }
                } label: {
                    Text("Resend code")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppTheme.surfaceSecondary, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.strongBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(authService.isLoading)
            }

            // Open email app
            Button {
                openEmailApp()
            } label: {
                Text("Open Email App")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppTheme.surfaceSecondary, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.strongBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Back button — returns to main login screen
            Button {
                code = ""
                authService.returnToLogin()
            } label: {
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .overlay {
            if authService.isLoading {
                ProgressView()
                    .tint(.primary)
            }
        }
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        VStack(spacing: 10) {
            // Divider with "or" — visible styling
            HStack(spacing: 12) {
                Rectangle().fill(AppTheme.strongBorder).frame(height: 0.5)
                Text("or")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Rectangle().fill(AppTheme.strongBorder).frame(height: 0.5)
            }
            .padding(.vertical, 6)

            // Apple Sign In — custom button so logo size and label match Google exactly.
            // Taps invoke the native Sign In with Apple flow via authService.
            Button {
                Task { await authService.signInWithApple() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 20, height: 20)
                    Text("Continue with Apple")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }
            .buttonStyle(.plain)

            // Google Sign In — outline pill with accurate multi-color Google SVG logo
            Button {
                Task { await authService.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleLogoView()
                        .frame(width: 20, height: 20)
                    Text("Continue with Google")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppTheme.surfaceSecondary, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.strongBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .disabled(authService.isLoading)
        .opacity(authService.isLoading ? 0.6 : 1)
        .overlay {
            if authService.isLoading {
                ProgressView()
                    .tint(.primary)
            }
        }
    }

    // MARK: - Footer (only on main login page, hidden on OTP page)

    private var footer: some View {
        VStack(spacing: 0) {
            // Extra breathing room between Google button and this row
            Button {
                authService.continueAsGuest()
            } label: {
                Text("Continue without account")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)

            // Terms / Privacy pushed further down with generous top padding
            // Links open the respective legal pages on todus.app
            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://todus.app/terms") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Terms of Service")
                }
                Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3)
                Button {
                    if let url = URL(string: "https://todus.app/privacy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Privacy Policy")
                }
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.7))
            .buttonStyle(.plain)
            .padding(.top, 28)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
            Spacer()
        }
        .padding(14)
        .background(
            Color.red.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Open Email App

    /// Opens the user's default email app via mailto: which respects the iOS default mail app setting.
    private func openEmailApp() {
        // mailto: opens the user's configured default email app (Gmail, Outlook, etc.)
        if let url = URL(string: "mailto:") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Google Logo

/// Pixel-accurate Google "G" logo — paths converted 1:1 from the official Google SVG
/// (viewBox 0 0 24 24). Scaled proportionally to whatever frame is applied.
private struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            // Scale all SVG coordinates (24×24 viewBox) to the rendered frame
            let s = size.width / 24.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Blue #4285F4
            // M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z
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
            // M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z
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
            // M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z
            var yellow = Path()
            yellow.move(to: pt(5.84, 14.09))
            yellow.addCurve(to: pt(5.49, 12.00),
                            control1: pt(5.62, 13.43), control2: pt(5.49, 12.73))
            // Smooth cubic (S): reflected cp1 from previous cp2
            yellow.addCurve(to: pt(5.84, 9.91),
                            control1: pt(5.49, 11.27), control2: pt(5.62, 10.57))
            yellow.addLine(to: pt(5.84, 7.07))
            yellow.addLine(to: pt(2.18, 7.07))
            yellow.addCurve(to: pt(1.00, 12.00),
                            control1: pt(1.43, 8.55), control2: pt(1.00, 10.22))
            // Smooth cubic S: reflected cp1 from previous cp2 (1, 10.22) → (1, 13.78)
            yellow.addCurve(to: pt(2.18, 16.93),
                            control1: pt(1.00, 13.78), control2: pt(1.43, 15.45))
            yellow.addLine(to: pt(5.03, 14.71))
            yellow.addLine(to: pt(5.84, 14.09))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(red: 0.980, green: 0.737, blue: 0.020)))

            // Red #EA4335
            // M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z
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
