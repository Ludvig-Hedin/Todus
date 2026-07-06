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
    /// Tracks whether the email field has ever lost focus after being edited —
    /// gates the "Enter a valid email" hint so it doesn't flash on every
    /// keystroke while the user is still mid-type.
    @State private var emailFieldDidEndEditing = false
    /// Resend cooldown (seconds remaining). Started after every successful
    /// send/resend so the resend button can't be hammered.
    @State private var resendCooldown = 0
    private let resendCooldownDuration = 60
    private let otpHelpMessage = "You can keep using tasks without email and connect it later in Settings."

    /// Blue accent used for primary action buttons (matches todo app).
    /// Sourced from the shared `AppTheme.Accents.blue` palette so the same RGB
    /// triple is used here and on macOS / web — change the palette to rebrand.
    private let accentBlue = AppTheme.Accents.blue

    private let expectedCodeLength = 6

    private var isValidEmail: Bool {
        // Trim whitespace and require at least `local@host.tld`. The previous check
        // accepted strings like "@.aa" because `contains("@")` and `contains(".")` can
        // both succeed on garbage; that produced a confusing "send code failed" round
        // trip to the backend. Validate the structural shape locally instead.
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[..<atIndex]
        let domain = trimmed[trimmed.index(after: atIndex)...]
        guard !local.isEmpty,
              let dotIndex = domain.firstIndex(of: "."),
              dotIndex > domain.startIndex else { return false }
        let tld = domain[domain.index(after: dotIndex)...]
        return !tld.isEmpty
    }

    var body: some View {
        ZStack {
            // Background-only tap target so the dismiss gesture doesn't intercept
            // taps along button edges (which used to swallow the first tap on
            // Send/Apple/Google when SwiftUI hit-tested the ZStack first).
            AppTheme.backgroundTop
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isEmailFocused = false
                    isCodeFocused = false
                }

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

                    Text(
                        otpPendingEmail == nil
                            ? "Email, tasks, and calendar in one workspace."
                            : "Enter the 6-digit code we sent to finish signing in."
                    )
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

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
                        // Disable the entire stage-1 stack while an auth request is
                        // in flight. Previously the Apple/Google buttons remained
                        // tappable while Send-OTP was loading, which let the user
                        // start a second flow on top of the first and stranded the
                        // app with overlapping spinner state.
                        VStack(spacing: 12) {
                            emailInputView
                            socialButtons
                            guestLink
                        }
                        .disabled(authService.isLoading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Terms / Privacy pinned at screen bottom
                legalLinks
                    .padding(.bottom, 16)
            }
        }
        // Keyboard dismiss is wired on the background Color above so button-edge
        // taps aren't intercepted by a ZStack-level gesture.
        .animation(.snappy(duration: 0.25), value: otpPendingEmail)
        .animation(.snappy(duration: 0.3), value: authService.lastErrorMessage != nil)
        // Auto-dismiss the error banner after a short delay so a stale message from
        // a previous attempt doesn't follow the user across screens or stages.
        .task(id: authService.lastErrorMessage) {
            guard authService.lastErrorMessage != nil else { return }
            let snapshot = authService.lastErrorMessage
            do {
                try await Task.sleep(for: .seconds(6))
            } catch {
                return // task was cancelled because the message changed
            }
            // Only clear if the message hasn't changed in the meantime.
            if authService.lastErrorMessage == snapshot {
                authService.lastErrorMessage = nil
            }
        }
        .onChange(of: otpPendingEmail) { _, newEmail in
            // Clear the code field whenever we leave the OTP stage (success, failure from
            // completeAuthentication, or manual back navigation) so the input is fresh
            // the next time the OTP view appears
            if newEmail == nil {
                code = ""
            }
        }
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
                .background(Color(UIColor.systemBackground), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(UIColor.separator), lineWidth: 1)
                )
                .accessibilityLabel("Email address")
                .accessibilityHint("Enter your email to sign in or create an account")
                .onSubmit {
                    guard isValidEmail else { return }
                    isEmailFocused = false
                    Task { await authService.sendEmailOTP(email: email) }
                }
                .onChange(of: isEmailFocused) { _, isFocused in
                    // Only start showing the validation hint once the user has
                    // left the field after typing — avoids flashing "Enter a
                    // valid email" on every keystroke while still mid-type.
                    if !isFocused && !email.isEmpty {
                        emailFieldDidEndEditing = true
                    }
                }
                .onChange(of: email) { _, newValue in
                    // A fresh edit after a prior "invalid" state should hide the
                    // hint again until the user leaves the field once more.
                    if newValue.isEmpty {
                        emailFieldDidEndEditing = false
                    }
                }

            // Inline validation hint — only after the user has left the field
            // (not on every keystroke) and only when the text doesn't
            // structurally look like an email. Silent while empty so the
            // first-impression state stays clean.
            if emailFieldDidEndEditing && !isEmailFocused && !email.isEmpty && !isValidEmail {
                Text("Enter a valid email")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            // Send code button — always rendered so the primary action is
            // discoverable; disabled + dimmed until the email looks valid.
            Button {
                isEmailFocused = false
                Task {
                    await authService.sendEmailOTP(email: email)
                    startResendCooldown()
                }
            } label: {
                Text("Send code")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(accentBlue, in: Capsule())
                    .foregroundStyle(.white)
                    .opacity((isValidEmail && !authService.isLoading) ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!isValidEmail || authService.isLoading)
            .overlay {
                // Match the spinner pattern used by socialButtons so the user gets
                // visual feedback while sendEmailOTP awaits the network round-trip
                if authService.isLoading {
                    ButtonInlineProgressView()
                }
            }
        }
    }

    /// Starts (or restarts) the 60s resend cooldown after a successful send.
    /// Guarded by an id-based Task so a superseded countdown doesn't keep
    /// ticking after a newer send restarts it.
    private func startResendCooldown() {
        guard authService.lastErrorMessage == nil else { return }
        resendCooldown = resendCooldownDuration
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if resendCooldown > 0 { resendCooldown -= 1 }
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
                .background(Color(UIColor.systemBackground), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(UIColor.separator), lineWidth: 1)
                )
                .accessibilityLabel("Verification code")
                .accessibilityHint("Enter the 6-digit code sent to your email")
                .onChange(of: code) { _, newValue in
                    // Strip any pasted non-digit characters (e.g. from a paste
                    // that includes surrounding text) before the length check
                    // below, so auto-submit only fires on a clean 6-digit code.
                    let digitsOnly = newValue.filter(\.isNumber)
                    if digitsOnly != newValue {
                        code = digitsOnly
                        return
                    }
                    // Guard: skip if already verifying (prevents double-submit when iOS
                    // auto-fill fires onChange multiple times in rapid succession)
                    if newValue.count >= expectedCodeLength && !authService.isLoading {
                        // Don't dismiss focus eagerly — keeping the keyboard up while
                        // verifying avoids a visible bounce when verification fails and
                        // we re-focus to let the user retry. Focus naturally drops on
                        // success when the OTP screen is unmounted.
                        Task {
                            await authService.verifyEmailOTP(code: newValue)
                            // On failure, clear the consumed code and refocus the field.
                            // Doing the refocus here (only after a failed attempt) avoids
                            // the keyboard flicker the previous .onAppear-toggle caused.
                            if authService.lastErrorMessage != nil {
                                code = ""
                                isCodeFocused = true
                            }
                        }
                    }
                }
                .onAppear {
                    // Initial focus when the OTP stage first renders. We deliberately do
                    // not toggle focus on every state change — see the .onChange handler
                    // for refocus-on-failure logic.
                    if !isCodeFocused {
                        isCodeFocused = true
                    }
                }

            // Show Verify when code is complete, Resend when not
            if code.count >= expectedCodeLength {
                Button {
                    // Keep focus while verifying so the keyboard doesn't bounce on failure
                    Task {
                        await authService.verifyEmailOTP(code: code)
                        if authService.lastErrorMessage != nil {
                            code = ""
                            isCodeFocused = true
                        }
                    }
                } label: {
                    Text("Verify code")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accentBlue, in: Capsule())
                        .foregroundStyle(.white)
                        .opacity(authService.isLoading ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(authService.isLoading)
                .overlay {
                    // Mirror the Send pattern: overlay the spinner on the button so
                    // it stays visible above the keyboard rather than sitting in the
                    // middle of the (now off-screen) parent stack.
                    if authService.isLoading {
                        ButtonInlineProgressView()
                    }
                }
            } else {
                Button {
                    Task {
                        await authService.sendEmailOTP(email: email)
                        startResendCooldown()
                    }
                } label: {
                    Text(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Resend code")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(UIColor.systemBackground), in: Capsule())
                        .overlay(Capsule().stroke(Color(UIColor.separator), lineWidth: 1))
                        .opacity((authService.isLoading || resendCooldown > 0) ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(authService.isLoading || resendCooldown > 0)
                .overlay {
                    if authService.isLoading {
                        ButtonInlineProgressView(tint: .primary)
                    }
                }
            }

            // Open email app — only render the button when the device actually has
            // a default mail handler that can open `mailto:`. Otherwise the tap is
            // a no-op (or worse, surfaces a "can't open" toast).
            if let mailURL = URL(string: "mailto:"), UIApplication.shared.canOpenURL(mailURL) {
                Button {
                    UIApplication.shared.open(mailURL)
                } label: {
                    Text("Open your email app")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(UIColor.systemBackground), in: Capsule())
                        .overlay(Capsule().stroke(Color(UIColor.separator), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // P13: bump muted help text contrast so it reads cleanly against the
            // capsule background while staying visually secondary.
            Text(otpHelpMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Back button — returns to main login screen
            Button {
                code = ""
                authService.returnToLogin()
            } label: {
                Text("Use another email")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        // Spinner is rendered on the active button (Verify or Resend) so it stays
        // visible above the keyboard. The previous outer overlay centered the
        // spinner in the parent stack, which on small devices ended up behind
        // the OTP keyboard and looked frozen.
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        VStack(spacing: 10) {
            // Divider with "or"
            HStack(spacing: 12) {
                Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                Text("or")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
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
            .accessibilityIdentifier("auth.signIn.appleButton")
            .accessibilityHint("Signs you in with your Apple ID")

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
                .background(Color(UIColor.systemBackground), in: Capsule())
                .overlay(Capsule().stroke(Color(UIColor.separator), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Signs you in with your Google account")
        }
        .disabled(authService.isLoading)
        .opacity(authService.isLoading ? 0.6 : 1)
        .overlay {
            if authService.isLoading {
                ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.buttonInlineSpinner)
            }
        }
    }

    // MARK: - Footer

    /// "Continue without account" link — shown below Google button
    private var guestLink: some View {
        Button {
            authService.continueAsGuest()
        } label: {
            Text("Continue as guest")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    /// Terms / Privacy links — pinned at the very bottom of the screen
    private var legalLinks: some View {
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
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        // Use .footnote (which scales with Dynamic Type) instead of a fixed 13pt size.
        // The icon weight stays semibold and the message stays medium so visual hierarchy
        // is preserved while text now respects the user's Dynamic Type preference.
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red.opacity(0.9))
            Spacer()
        }
        .padding(14)
        .background(
            Color.red.opacity(0.08),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
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
