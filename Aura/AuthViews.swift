import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

struct AuraAuthGatewayView: View {
    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case create = "Create Account"
    }

    private let defaultBackendBaseURL = "https://aurenda.up.railway.app"

    @EnvironmentObject var store: EventStore
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("backendAccountEmail") private var backendAccountEmail = ""
    @AppStorage("profileDisplayName") private var profileDisplayName = ""
    @AppStorage("aura.allowOfflineMode") private var allowOfflineMode = false
    @AppStorage("authHeroMode") private var authHeroMode = "collage"
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var groupName = "My First Group"
    @State private var groupType = "Family"
    @State private var joinCode = ""
    @State private var message = ""
    @State private var isWorking = false
    @State private var biometricLabel = ""
    @State private var showForgotPassword = false

    var body: some View {
        ZStack {
            AuraAuthBackgroundSlideshow(mode: authHeroMode)
                .ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Secure Access", systemImage: "lock.shield.fill")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(1.4)
                                .foregroundColor(.white.opacity(0.72))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08), in: Capsule())

                            Text("Aurenda")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("Your life, beautifully organized. Aurenda brings every circle into harmony.")
                                .font(.system(size: 16, weight: .medium))
                                .lineSpacing(3)
                                .foregroundColor(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 12) {
                        if !store.hasServerSession {
                            modeToggle

                            authField(icon: "envelope.fill") {
                                TextField(
                                    "",
                                    text: $email,
                                    prompt: Text("Email").foregroundColor(.white.opacity(0.9))
                                )
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.emailAddress)
                            }

                            authField(icon: "lock.fill") {
                                AuraSecureField(placeholder: "Password", text: $password, promptColor: .white.opacity(0.9))
                            }

                            if mode == .signIn {
                                Button("Forgot password?") { showForgotPassword = true }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            if mode == .create {
                                authField(icon: "person.fill") {
                                    TextField(
                                        "",
                                        text: $displayName,
                                        prompt: Text("Full Name").foregroundColor(.white.opacity(0.9))
                                    )
                                }
                            }

                            Button {
                                isWorking = true
                                message = ""
                                Task {
                                    let result: Result<Void, Error>
                                    if mode == .create {
                                        result = await store.registerServerAccount(email: email, password: password, displayName: displayName)
                                    } else {
                                        result = await store.loginServerAccount(email: email, password: password)
                                    }
                                    await MainActor.run {
                                        isWorking = false
                                        switch result {
                                        case .success:
                                            password = ""
                                            backendAccountEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                profileDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                            }
                                            message = mode == .create ? "Account created. Create or join your first group." : "Welcome back. Select or create a group to continue."
                                        case .failure(let error):
                                            message = error.localizedDescription
                                        }
                                    }
                                }
                            } label: {
                                Label(mode == .create ? "Create Account" : "Enter Aurenda", systemImage: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        LinearGradient(
                                            colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                    .shadow(color: AuraThemePalette.current.accentStart.opacity(0.35), radius: 18, y: 8)
                            }
                            .buttonStyle(AuraSoftPressButtonStyle())
                            .foregroundStyle(.white)
                            .disabled(backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (mode == .create && displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                            biometricActionRow
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(AuraThemePalette.current.accentStart)
                                Text("Signed in as \(backendAccountEmail)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Sign Out") {
                                    store.clearServerSession()
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .tint(.white.opacity(0.85))
                            }
                            .padding(.horizontal, 4)
                        }

                        if store.hasServerSession {
                            Divider().padding(.vertical, 6)

                            Text("SET UP YOUR GROUP")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !store.serverGroups.isEmpty {
                                Picker("Active Group", selection: Binding(
                                    get: { store.activeServerGroupId },
                                    set: { store.setActiveServerGroup(id: $0) }
                                )) {
                                    ForEach(store.serverGroups) { record in
                                        Text("\(record.group.name) (\(record.membership.role))")
                                            .tag(record.group.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.white)
                            }

                            TextField(
                                "",
                                text: $groupName,
                                prompt: Text("Group Name").foregroundColor(.white.opacity(0.9))
                            )
                                .authInputStyle()

                            Picker("Group type", selection: $groupType) {
                                Text("Family").tag("Family")
                                Text("Roommates").tag("Roommates")
                                Text("Couple").tag("Couple")
                                Text("Church").tag("Church")
                                Text("Travel").tag("Travel")
                                Text("Study").tag("Study")
                                Text("Custom").tag("Custom")
                            }
                            .pickerStyle(.menu)
                            .tint(.white)

                            Button {
                                isWorking = true
                                message = ""
                                Task {
                                    let result = await store.createServerGroup(name: groupName, type: groupType)
                                    await MainActor.run {
                                        isWorking = false
                                        switch result {
                                        case .success(let code):
                                            joinCode = code
                                            message = "Group created. Code: \(code)"
                                        case .failure(let error):
                                            message = error.localizedDescription
                                        }
                                    }
                                }
                            } label: {
                                Label("Create Group", systemImage: "person.3.sequence.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)

                            HStack(spacing: 10) {
                                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                                Text("OR JOIN WITH A CODE")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1.0)
                                    .foregroundColor(.white.opacity(0.5))
                                    .fixedSize()
                                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                            }
                            .padding(.vertical, 4)

                            TextField(
                                "",
                                text: $joinCode,
                                prompt: Text("Join Code").foregroundColor(.white.opacity(0.9))
                            )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .authInputStyle()

                            Button {
                                isWorking = true
                                message = ""
                                Task {
                                    let result = await store.joinServerGroup(code: joinCode)
                                    await MainActor.run {
                                        isWorking = false
                                        switch result {
                                        case .success:
                                            message = "Joined group successfully."
                                        case .failure(let error):
                                            message = error.localizedDescription
                                        }
                                    }
                                }
                            } label: {
                                Label("Join Group", systemImage: "person.2.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if isWorking { ProgressView().tint(.white) }

                        if !message.isEmpty {
                            Text(message)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isMessageError ? Color.red.opacity(0.95) : Color.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    (isMessageError ? Color.red : AuraThemePalette.current.accentStart)
                                        .opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                    }
                        .padding(18)
                        .auraGlassCard(radius: AuraDesignTokens.Radius.xl)
                        .environment(\.colorScheme, .dark)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            email = backendAccountEmail
            displayName = profileDisplayName
            if backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                backendBaseURL = defaultBackendBaseURL
            }
            store.updateBackendBaseURL(backendBaseURL)
            updateBiometricLabel()
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(email: email).environmentObject(store)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                modeButton(for: m)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func modeButton(for m: Mode) -> some View {
        let isSelected = mode == m
        let fill: AnyShapeStyle = isSelected
            ? AnyShapeStyle(LinearGradient(
                colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                startPoint: .leading,
                endPoint: .trailing
            ))
            : AnyShapeStyle(Color.clear)
        return Button {
            AuraHaptics.tap(.light)
            withAnimation(AuraMotion.smooth) { mode = m }
        } label: {
            Text(m.rawValue)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func authField<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 18)
            content()
        }
        .foregroundColor(.white)
        .tint(.white)
        .padding(.horizontal, AuraDesignTokens.Spacing.sm)
        .padding(.vertical, AuraDesignTokens.Spacing.sm)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: AuraDesignTokens.Stroke.subtle)
        )
    }

    @ViewBuilder
    private var biometricActionRow: some View {
        if supportsBiometrics {
            VStack(spacing: 8) {
                Button {
                    authenticateWithBiometrics()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: biometricSymbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(biometricLabel.isEmpty ? biometricTitle : biometricLabel)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: AuraThemePalette.current.accentStart.opacity(0.18), radius: 16, y: 8)
                    .shadow(color: AuraThemePalette.current.accentEnd.opacity(0.12), radius: 24, y: 14)
                }
                .buttonStyle(AuraSoftPressButtonStyle())

                Text("Secure unlock with Face ID or Touch ID.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    private var biometricTitle: String {
        biometricType == .faceID ? "Sign in with Face ID" : "Sign in with Touch ID"
    }

    private var biometricSymbol: String {
        biometricType == .faceID ? "faceid" : "touchid"
    }

    private var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    private var supportsBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private func updateBiometricLabel() {
        biometricLabel = supportsBiometrics ? biometricTitle : ""
    }

    private var isMessageError: Bool {
        let lower = message.lowercased()
        return lower.contains("failed")
            || lower.contains("invalid")
            || lower.contains("error")
            || lower.contains("unavailable")
            || lower.contains("expired")
            || lower.contains("not found")
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            message = "Biometrics are not available on this device."
            return
        }

        let reason = "Unlock Aurenda with Face ID or Touch ID."
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
            DispatchQueue.main.async {
                if success {
                    allowOfflineMode = true
                    message = "Biometrics verified. Opening your local workspace."
                } else {
                    message = evalError?.localizedDescription ?? "Biometric authentication failed."
                }
            }
        }
    }
}

/// Reset by emailed code: request a code, then enter it with a new password.
/// Success signs the user straight in.
struct ForgotPasswordView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @State var email: String
    @State private var code = ""
    @State private var newPassword = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var message = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                        .disabled(codeSent)
                } footer: {
                    Text(codeSent
                         ? "If an account uses this email, a 6-digit code is on its way. It expires in 15 minutes."
                         : "We'll email you a 6-digit code.")
                }
                if codeSent {
                    Section {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        AuraSecureField(placeholder: "New password (min 8)", text: $newPassword)
                    }
                }
                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                Section {
                    Button(codeSent ? "Reset Password" : "Send Code") {
                        Task { await submit() }
                    }
                    .disabled(isWorking || !canSubmit)
                    if codeSent {
                        Button("Send a new code") {
                            code = ""
                            Task { await sendCode() }
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        let hasEmail = email.contains("@")
        return codeSent ? hasEmail && code.count == 6 && newPassword.count >= 8 : hasEmail
    }

    private func submit() async {
        if codeSent {
            isWorking = true
            let result = await store.resetPassword(email: email, code: code, newPassword: newPassword)
            isWorking = false
            switch result {
            case .success:
                AuraHaptics.success()
                dismiss()
            case .failure(let error):
                message = error.localizedDescription
            }
        } else {
            await sendCode()
        }
    }

    private func sendCode() async {
        isWorking = true
        message = ""
        let result = await store.requestPasswordReset(email: email)
        isWorking = false
        switch result {
        case .success:
            codeSent = true
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

/// A password field with a show/hide toggle -- plain SecureField/TextField
/// give no way to check what you typed before submitting. `promptColor` is
/// only for fields on a dark/custom background (like the auth gateway); leave
/// it nil for a plain Form row, which already gets the right color for free.
struct AuraSecureField: View {
    let placeholder: String
    @Binding var text: String
    var promptColor: Color? = nil

    @State private var isRevealed = false

    var body: some View {
        HStack {
            Group {
                if let promptColor {
                    if isRevealed {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(promptColor))
                    } else {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(promptColor))
                    }
                } else {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14))
                    .foregroundColor(promptColor?.opacity(0.7) ?? .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AuraAuthBackgroundSlideshow: View {
    let mode: String
    @State private var slideIndex = 0

    private let slides: [(symbol: String, title: String, subtitle: String, start: String, end: String)] = [
        ("square.stack.3d.up.fill", "Multi-Group Workspaces", "Family, roommates, church, travel, study", "0B1220", "1D4ED8"),
        ("person.crop.circle.badge.checkmark", "Personal Command", "One merged view across your life circles", "0F172A", "0F766E"),
        ("bolt.horizontal.circle.fill", "Conflict Intercept", "Catch overlaps early and auto-suggest better slots", "1F2937", "9A3412")
    ]

    private var visibleSlides: [(symbol: String, title: String, subtitle: String, start: String, end: String)] {
        mode == "single" ? [slides[0]] : slides
    }

    var body: some View {
        let p = AuraThemePalette.current
        GeometryReader { geo in
            ZStack {
                ForEach(Array(visibleSlides.enumerated()), id: \.offset) { index, slide in
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: slide.start), Color(hex: slide.end)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 280, height: 280)
                            .blur(radius: 26)
                            .offset(x: -120, y: -210)

                        Circle()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: 320, height: 320)
                            .blur(radius: 28)
                            .offset(x: 140, y: 260)

                        EmptyView()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [Color.black.opacity(0.22), Color.black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(index == slideIndex ? 1 : 0)
                    .scaleEffect(index == slideIndex ? 1.03 : 1.11)
                    .animation(.easeInOut(duration: 1.0), value: slideIndex)
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.5), Color.black.opacity(0.2), Color.black.opacity(0.64)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                EmptyView()
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(
                LinearGradient(
                    colors: [p.backgroundStart, p.backgroundEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .onAppear {
            slideIndex = 0
        }
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            guard mode != "single", visibleSlides.count > 1 else { return }
            withAnimation(.easeInOut(duration: 1.0)) {
                slideIndex = (slideIndex + 1) % visibleSlides.count
            }
        }
    }
}

extension View {
    func authInputStyle() -> some View {
        self
            .foregroundColor(.white)
            .tint(.white)
            .padding(.horizontal, AuraDesignTokens.Spacing.sm)
            .padding(.vertical, AuraDesignTokens.Spacing.sm)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.md, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: AuraDesignTokens.Stroke.subtle)
            )
    }
}
