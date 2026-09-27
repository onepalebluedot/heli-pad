import SwiftUI
import AuthenticationServices

extension FamilyAccount {
    /// What to call this person on screen: their name, else the username or
    /// email they signed in with.
    var shownName: String {
        if !displayName.isEmpty { return displayName }
        if let username { return username }
        return email ?? "Apple account"
    }

    var signInMethod: String {
        if let username { return "Username · \(username)" }
        return "Signed in with Apple"
    }
}

/// Entry for a new installation and for an existing local family enabling
/// sharing. A caregiver name is chosen separately after family membership.
struct FamilyAccountView: View {
    @ObservedObject var store: AppStore
    var isFirstRun: Bool
    var initialInviteCode: String = ""
    var onFinished: () -> Void

    private enum CredentialMode: String, CaseIterable {
        case create = "Create account"
        case signIn = "Sign in"
    }

    @State private var nonce: String?
    @State private var profile: FamilyProfile?
    @State private var familyName = ""
    @State private var inviteCode = ""
    @State private var invitePreview: FamilyInvitePreview?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var credentialMode: CredentialMode = .create
    @State private var accountName = ""
    @State private var username = ""
    @State private var password = ""

    private let api = FamilyAccountAPI.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your family, together")
                            .font(HeliTypography.headline(25))
                            .foregroundColor(HeliColors.greenInk)
                        Text(profile == nil
                             ? "Create an account or sign in with Apple. Then start a family, or join one you were invited to."
                             : "Start a family, or join one you were invited to.")
                            .font(HeliTypography.body(14))
                            .foregroundColor(HeliColors.mutedGray)
                    }

                    if let profile {
                        signedInContent(profile)
                    } else {
                        signInContent
                    }

                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(HeliTypography.body(13))
                            .foregroundColor(HeliColors.clayText)
                    }

                    if isFirstRun {
                        Text("Family data stays private to invited members. Your caregiver profile controls which stops appear first on this phone.")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle("Family account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstRun {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onFinished)
                    }
                }
            }
        }
        .task { await loadAccount() }
        .onAppear { inviteCode = initialInviteCode }
        .onChange(of: initialInviteCode) { _, code in inviteCode = code }
        .onChange(of: inviteCode) { _, _ in invitePreview = nil }
    }

    // MARK: - Signed out

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SignInWithAppleButton(.signIn, onRequest: { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonce
            }, onCompletion: handleAppleResult)
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(nonce == nil || busy)
            .accessibilityHint(nonce == nil ? "Preparing secure sign-in" : "")

            // The Apple button needs a server nonce; the username form does
            // not, so a failed challenge only blocks Apple, not the whole screen.
            if nonce == nil && !busy {
                if errorMessage != nil {
                    Button("Retry Sign in with Apple") { Task { await prepareChallenge() } }
                        .font(HeliTypography.actionButton(13))
                        .foregroundColor(HeliColors.forestGreen)
                        .frame(minHeight: 44)
                } else {
                    ProgressView("Preparing secure sign-in…")
                        .font(HeliTypography.caption(12))
                }
            }

            HStack(spacing: 10) {
                Rectangle().fill(HeliColors.sageRule).frame(height: 1)
                Text("or use a username")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize()
                Rectangle().fill(HeliColors.sageRule).frame(height: 1)
            }
            .accessibilityElement(children: .combine)

            Picker("Account", selection: $credentialMode) {
                ForEach(CredentialMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: credentialMode) { _, _ in errorMessage = nil }

            VStack(alignment: .leading, spacing: 10) {
                if credentialMode == .create {
                    TextField("Your name", text: $accountName)
                        .textContentType(.name)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textContentType(credentialMode == .create ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canSubmitCredentials { Task { await submitCredentials() } } }
                if credentialMode == .create {
                    Text("At least 8 characters. Your family sees your name, not your username.")
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }

            Button {
                Task { await submitCredentials() }
            } label: {
                Text(credentialMode.rawValue)
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.cardWarmWhite)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HeliColors.forestGreen.opacity(canSubmitCredentials ? 1 : 0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitCredentials)
        }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitCredentials: Bool {
        guard !busy, trimmedUsername.count >= 3 else { return false }
        return credentialMode == .create ? password.count >= 8 : !password.isEmpty
    }

    // MARK: - Signed in

    private func signedInContent(_ profile: FamilyProfile) -> some View {
        let newUser = !store.hasCompletedOnboarding
        let availableFamilies = profile.families.filter {
            newUser || (store.isManagedFamily && $0.id == store.cloudHouseholdID)
        }
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                AvatarDisc(name: profile.account.shownName, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.account.shownName)
                        .font(HeliTypography.cardTitle(15))
                        .foregroundColor(HeliColors.greenInk)
                    Text(profile.account.signInMethod)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                }
                Spacer()
                Button("Switch") { Task { await switchAccount() } }
                    .font(HeliTypography.actionButton(13))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(busy)
                    .accessibilityLabel("Use a different account")
            }
            .accessibilityElement(children: .contain)

            if !availableFamilies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR FAMILIES")
                        .font(HeliTypography.eyebrow(11))
                        .foregroundColor(HeliColors.mutedGray)
                    ForEach(availableFamilies) { family in
                        Button {
                            Task { await open(family) }
                        } label: {
                            HStack {
                                Text(family.name)
                                Spacer()
                                Text(family.role.capitalized)
                                    .font(HeliTypography.caption(11))
                                Image(systemName: "chevron.right")
                            }
                            .font(HeliTypography.body(14))
                            .foregroundColor(HeliColors.greenInk)
                            .padding(14)
                            .frame(minHeight: 44)
                            .background(HeliColors.cardWarmWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel("Open \(family.name)")
                        .accessibilityValue(family.role.capitalized)
                    }
                }
            }

            if store.isManagedFamily && availableFamilies.isEmpty {
                Text("This account is not a member of the family on this phone. Switch to the account that set it up to restore access.")
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.clayText)
            }

            if !store.isManagedFamily {
                VStack(alignment: .leading, spacing: 10) {
                    Text(newUser ? "Start a family" : "Share this household")
                        .font(HeliTypography.headline(17))
                        .foregroundColor(HeliColors.greenInk)
                    if !newUser {
                        Text("Everything on this phone moves into the family, so people you invite see the same schedule and lists.")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    TextField("Family name, e.g. The Vincents", text: $familyName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.organizationName)
                    Button(newUser ? "Create family" : "Create family and share") {
                        Task { await createFamily() }
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.cardWarmWhite)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HeliColors.forestGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(busy || familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if newUser {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Join with an invitation")
                        .font(HeliTypography.headline(17))
                        .foregroundColor(HeliColors.greenInk)
                    TextField("Invitation code", text: $inviteCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    if let invitePreview {
                        Text("Invitation to \(invitePreview.name)")
                            .font(HeliTypography.body(13))
                            .foregroundColor(HeliColors.greenInk)
                    }
                    Button(invitePreview == nil ? "Find family" : "Join \(invitePreview!.name)") {
                        Task { await previewOrJoin() }
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(HeliColors.forestTint)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(busy || inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadAccount() async {
        errorMessage = nil
        guard AppConfig.familyAPIURL != nil else {
            errorMessage = FamilyAccountError.unavailable.localizedDescription
            return
        }
        if api.hasSession {
            do { profile = try await api.profile(); return }
            catch FamilyAccountError.notSignedIn { try? api.clearSession() }
            catch { errorMessage = error.localizedDescription; return }
        }
        await prepareChallenge()
    }

    private func prepareChallenge() async {
        errorMessage = nil
        do { nonce = try await api.challenge() }
        catch { errorMessage = error.localizedDescription }
    }

    private func switchAccount() async {
        busy = true
        defer { busy = false }
        do {
            try await api.logout()
            profile = nil
            nonce = nil
            password = ""
            await prepareChallenge()
        } catch { errorMessage = error.localizedDescription }
    }

    private func submitCredentials() async {
        guard canSubmitCredentials else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            switch credentialMode {
            case .create:
                profile = try await api.register(
                    username: trimmedUsername, password: password,
                    displayName: accountName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            case .signIn:
                profile = try await api.login(username: trimmedUsername, password: password)
            }
            password = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let usedNonce = nonce else {
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            else { errorMessage = "Apple sign-in did not return an identity token. Try again." }
            return
        }
        nonce = nil
        busy = true
        errorMessage = nil
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
        Task {
            defer { busy = false }
            do { profile = try await api.signIn(identityToken: token, nonce: usedNonce, displayName: name) }
            catch {
                let message = error.localizedDescription
                await prepareChallenge()
                if nonce != nil { errorMessage = message }
            }
        }
    }

    private func createFamily() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let existing = store.hasCompletedOnboarding
            if existing { _ = try store.lists.archive.validated() }
            let family = try await api.createFamily(
                name: familyName.trimmingCharacters(in: .whitespacesAndNewlines),
                state: existing ? store.accountExportState() : nil
            )
            try store.useCreatedFamily(id: family.id, uploadedState: existing)
            if existing { await store.lists.sync() }
            if !existing { store.showOnboarding = true }
            onFinished()
        } catch { errorMessage = error.localizedDescription }
    }

    private func open(_ family: FamilySummary) async {
        if store.isManagedFamily && store.cloudHouseholdID == family.id { onFinished(); return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await store.joinManagedFamily(id: family.id)
            onFinished()
        } catch { errorMessage = error.localizedDescription }
    }

    private func previewOrJoin() async {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            if invitePreview == nil {
                invitePreview = try await api.previewInvite(code: code)
            } else {
                let familyID = try await api.acceptInvite(code: code)
                try await store.joinManagedFamily(id: familyID)
                onFinished()
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

struct FamilyInviteView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var invite: FamilyInvite?
    @State private var busy = false
    @State private var isOwner: Bool?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Invite someone to your family")
                    .font(HeliTypography.headline(21))
                    .foregroundColor(HeliColors.greenInk)
                Text("They’ll create an account or sign in with Apple, enter this code, then choose their caregiver profile. The code works once and expires after seven days.")
                    .font(HeliTypography.body(14))
                    .foregroundColor(HeliColors.mutedGray)

                if isOwner == false {
                    Text("Only the family owner can create invitations.")
                        .font(HeliTypography.body(14))
                        .foregroundColor(HeliColors.mutedGray)
                } else if let invite {
                    Text(invite.code)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundColor(HeliColors.greenInk)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    ShareLink(item: invitationMessage(invite)) {
                        Label("Share invitation", systemImage: "square.and.arrow.up")
                            .font(HeliTypography.actionButton(14))
                            .foregroundColor(HeliColors.cardWarmWhite)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(HeliColors.forestGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else if isOwner == true {
                    Button("Create invitation") { Task { await createInvite() } }
                        .font(HeliTypography.actionButton(14))
                        .foregroundColor(HeliColors.cardWarmWhite)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(HeliColors.forestGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(busy)
                }
                if busy { ProgressView() }
                if let errorMessage {
                    Text(errorMessage)
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.clayText)
                }
                Spacer()
            }
            .padding(22)
            .background(HeliColors.canvasIvory)
            .navigationTitle("Family invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            do {
                let profile = try await FamilyAccountAPI.shared.profile()
                isOwner = profile.families.first { $0.id == store.cloudHouseholdID }?.role == "owner"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func createInvite() async {
        busy = true
        defer { busy = false }
        do { invite = try await FamilyAccountAPI.shared.createInvite(familyID: store.cloudHouseholdID) }
        catch { errorMessage = error.localizedDescription }
    }

    private func invitationMessage(_ invite: FamilyInvite) -> String {
        let link = AppConfig.familyAPIURL?
            .appendingPathComponent("invite")
            .appendingPathComponent(invite.code)
            .absoluteString ?? "helipad://invite/\(invite.code)"
        return "Join my family in HeliPad: \(link)\n\nInvitation code: \(invite.code)"
    }
}
