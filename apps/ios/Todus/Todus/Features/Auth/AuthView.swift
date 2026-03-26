import SwiftUI
import AuthenticationServices

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
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isEmailFocused)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceSecondary, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.strongBorder, lineWidth: 1)
                )

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

            // Apple Sign In — uses native button for guaranteed correct rendering.
            // Black on light mode, white on dark mode (Apple's standard).
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { _ in }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .overlay {
                Color.clear
                    .contentShape(Capsule())
                    .onTapGesture {
                        Task { await authService.signInWithApple() }
                    }
            }

            // Google Sign In — outline pill with proper Google "G" SVG-style logo
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
        VStack(spacing: 14) {
            Button {
                authService.continueAsGuest()
            } label: {
                Text("Continue without account")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text("Terms of Service")
                Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3)
                Text("Privacy Policy")
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.top, 8)
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

// MARK: - Google Logo (proper "G" shape)

/// Accurate multi-color Google "G" logo using SVG-path-style drawing
private struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r = min(w, h) / 2 * 0.9 // Outer radius

            // Google "G" is a circle with a gap on the right + a horizontal bar
            // Colors: top-right = blue, bottom-right = red, bottom-left = yellow, top-left = green

            // Blue arc (right side, from -30° to 90° clockwise = top-right quadrant)
            drawArc(in: &context, center: CGPoint(x: cx, y: cy), radius: r,
                     startAngle: .degrees(-30), endAngle: .degrees(70),
                     color: Color(red: 0.26, green: 0.52, blue: 0.96))

            // Green arc (bottom-right)
            drawArc(in: &context, center: CGPoint(x: cx, y: cy), radius: r,
                     startAngle: .degrees(70), endAngle: .degrees(160),
                     color: Color(red: 0.20, green: 0.66, blue: 0.33))

            // Yellow arc (bottom-left)
            drawArc(in: &context, center: CGPoint(x: cx, y: cy), radius: r,
                     startAngle: .degrees(160), endAngle: .degrees(250),
                     color: Color(red: 0.98, green: 0.74, blue: 0.02))

            // Red arc (top-left to top)
            drawArc(in: &context, center: CGPoint(x: cx, y: cy), radius: r,
                     startAngle: .degrees(250), endAngle: .degrees(330),
                     color: Color(red: 0.92, green: 0.26, blue: 0.21))

            // Inner circle cutout (creates the "C" shape)
            let innerR = r * 0.6
            let innerRect = CGRect(x: cx - innerR, y: cy - innerR,
                                    width: innerR * 2, height: innerR * 2)
            context.fill(Circle().path(in: innerRect),
                         with: .color(AppTheme.surfaceSecondary))

            // Horizontal bar (the "dash" in the G, extending right from center)
            let barH = r * 0.28
            let barRect = CGRect(x: cx - r * 0.05, y: cy - barH / 2,
                                  width: r * 0.95, height: barH)
            context.fill(
                RoundedRectangle(cornerRadius: barH * 0.15).path(in: barRect),
                with: .color(Color(red: 0.26, green: 0.52, blue: 0.96))
            )
        }
    }

    private func drawArc(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                          startAngle: Angle, endAngle: Angle, color: Color) {
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                     startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}
