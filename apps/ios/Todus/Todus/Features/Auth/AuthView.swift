import SwiftUI
import AuthenticationServices

/// Sign-in screen — matches the todo app's auth flow.
/// Stage 1: Email input + social buttons (Apple, Google).
/// Stage 2: 6-digit OTP code entry with auto-submit.
struct AuthView: View {
    @Environment(AppServices.self) private var services

    private var authService: AuthService { services.authService }

    @State private var email = ""
    @State private var code = ""
    @FocusState private var isInputFocused: Bool

    /// Blue accent used for primary action buttons (matches todo app)
    private let accentBlue = Color(red: 0.25, green: 0.48, blue: 1.0)

    private let expectedCodeLength = 6

    private var isValidEmail: Bool {
        let regex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Brand logo + title
                VStack(spacing: 8) {
                    Image("BrandLogo")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .padding(.bottom, 8)

                    Text("Welcome to Todus")
                        .font(.system(size: 24, weight: .semibold))

                    Text("Your AI agent for emails")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.5))

                    Text(otpPendingEmail == nil ? "Sign in to get started" : "Enter the code sent to your email")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.4))
                        .padding(.top, 2)
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
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Footer
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
                .padding(.bottom, 40)
            }
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
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isInputFocused)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )

            // Send code button — only visible when email is valid
            if isValidEmail {
                Button {
                    Task { await authService.sendEmailOTP(email: email) }
                } label: {
                    Text("Send magic link")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accentBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .focused($isInputFocused)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
                .onChange(of: code) { _, newValue in
                    // Auto-submit when 6 digits are entered
                    if newValue.count >= expectedCodeLength {
                        Task { await authService.verifyEmailOTP(code: newValue) }
                    }
                }
                .onAppear {
                    // Auto-focus the code input
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isInputFocused = true
                    }
                }

            // Verify button
            Button {
                Task { await authService.verifyEmailOTP(code: code) }
            } label: {
                Text("Verify code")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        code.count >= expectedCodeLength ? accentBlue : Color.secondary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(code.count >= expectedCodeLength ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(code.count < expectedCodeLength || authService.isLoading)

            // Open email app button
            Button {
                openEmailApp()
            } label: {
                Text("Open Email App")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Use another email
            Button {
                code = ""
                authService.returnToLogin()
            } label: {
                Text("Use another email")
                    .font(.system(size: 13, weight: .medium))
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
            // Divider with "or"
            HStack {
                Rectangle().fill(AppTheme.cardBorder).frame(height: 1)
                Text("or")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                Rectangle().fill(AppTheme.cardBorder).frame(height: 1)
            }
            .padding(.vertical, 4)

            // Apple Sign In — primary filled (white pill on dark)
            Button {
                Task { await authService.signInWithApple() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Continue with Apple")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.primary, in: Capsule())
                .foregroundStyle(AppTheme.backgroundTop)
            }
            .buttonStyle(.plain)

            // Google Sign In — outline style
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
                .background(AppTheme.surfacePrimary, in: Capsule())
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

    /// Opens the user's preferred email app — tries Gmail, Outlook, Spark, then Apple Mail.
    private func openEmailApp() {
        let emailApps: [(scheme: String, name: String)] = [
            ("googlegmail:///", "Gmail"),
            ("ms-outlook://inbox", "Outlook"),
            ("readdle-spark://", "Spark"),
            ("message://", "Apple Mail"),
        ]
        for app in emailApps {
            if let url = URL(string: app.scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        // Fallback — opens whatever handles mailto
        if let url = URL(string: "mailto:") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Google Logo

/// Multi-color Google "G" logo matching the RN SVG icon
private struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1

            drawArc(in: &context, center: center, radius: radius,
                     startAngle: .degrees(-45), endAngle: .degrees(45),
                     color: Color(red: 0.26, green: 0.52, blue: 0.96))
            drawArc(in: &context, center: center, radius: radius,
                     startAngle: .degrees(45), endAngle: .degrees(135),
                     color: Color(red: 0.20, green: 0.66, blue: 0.33))
            drawArc(in: &context, center: center, radius: radius,
                     startAngle: .degrees(135), endAngle: .degrees(225),
                     color: Color(red: 0.98, green: 0.74, blue: 0.02))
            drawArc(in: &context, center: center, radius: radius,
                     startAngle: .degrees(225), endAngle: .degrees(315),
                     color: Color(red: 0.92, green: 0.26, blue: 0.21))

            let innerRadius = radius * 0.55
            let innerRect = CGRect(
                x: center.x - innerRadius, y: center.y - innerRadius,
                width: innerRadius * 2, height: innerRadius * 2
            )
            context.fill(Circle().path(in: innerRect), with: .color(AppTheme.surfacePrimary))

            let barWidth = radius * 0.9
            let barHeight = radius * 0.35
            let barRect = CGRect(
                x: center.x - barWidth * 0.1,
                y: center.y - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            context.fill(
                RoundedRectangle(cornerRadius: 1).path(in: barRect),
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
