import SwiftUI
import AuthenticationServices

/// Entry for a new installation and for an existing local family enabling
/// sharing. A caregiver name is chosen separately after family membership.
struct FamilyAccountView: View {
    @ObservedObject var store: AppStore
    var isFirstRun: Bool
    var initialInviteCode: String = ""
    var previewOnly: Bool = false
    var onFinished: () -> Void

    @State private var nonce: String?
    @State private var profile: FamilyProfile?
    @State private var familyName = ""
    @State private var inviteCode = ""
    @State private var invitePreview: FamilyInvitePreview?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var previewAfterSignIn = false

    private let api = FamilyAccountAPI.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your family, together")
                            .font(HeliTypography.headline(25))
                            .foregroundColor(HeliColors.greenInk)
                        Text("Sign in with Apple to create a private family or join one you were invited to.")
                            .font(HeliTypography.body(14))
                            .foregroundColor(HeliColors.mutedGray)
                    }

                    if previewOnly {
                        Text("Preview only — your account and family data will not change.")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                        if previewAfterSignIn {
                            signedInContent(FamilyProfile(
                                account: FamilyAccount(id: "preview", displayName: "New tester", email: nil),
                                families: []
                            ))
                            Button("Back to sign-in screen") { previewAfterSignIn = false }
                                .font(HeliTypography.actionButton(13))
                        } else {
                            SignInWithAppleButton(.signIn, onRequest: { _ in }, onCompletion: { _ in })
                                .signInWithAppleButtonStyle(.black)
                                .frame(height: 50)
                                .allowsHitTesting(false)
                            Button("Preview after sign-in") { previewAfterSignIn = true }
                                .font(HeliTypography.actionButton(13))
                        }
                    } else if let profile {
                        signedInContent(profile)
                    } else {
                        SignInWithAppleButton(.signIn, onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = nonce
                        }, onCompletion: handleAppleResult)
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .disabled(nonce == nil || busy)

                        if nonce == nil {
                            if errorMessage != nil {
                                Button("Try again") { Task { await loadAccount() } }
                                    .font(HeliTypography.actionButton(14))
                            } else {
                                ProgressView("Preparing secure sign-in…")
                            }
                        }
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
                if !isFirstRun || previewOnly {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onFinished)
                    }
                }
            }
        }
        .task { if !previewOnly { await loadAccount() } }
        .onAppear { inviteCode = initialInviteCode }
        .onChange(of: initialInviteCode) { _, code in inviteCode = code }
        .onChange(of: inviteCode) { _, _ in invitePreview = nil }
    }

    private func signedInContent(_ profile: FamilyProfile) -> some View {
        let newUser = previewOnly || !store.hasCompletedOnboarding
        let availableFamilies = profile.families.filter {
            newUser || (store.isManagedFamily && $0.id == store.cloudHouseholdID)
        }
        return VStack(alignment: .leading, spacing: 20) {
            Text("Signed in as \(profile.account.displayName.isEmpty ? profile.account.email ?? "Apple account" : profile.account.displayName)")
                .font(HeliTypography.cardTitle(14))
                .foregroundColor(HeliColors.greenInk)

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
                    }
                }
            }

            if store.isManagedFamily && !previewOnly && availableFamilies.isEmpty {
                Text("This Apple ID is not a member of the family on this phone. Sign in with the original Apple ID to restore access.")
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.clayText)
                Button("Use another Apple ID") { Task { await switchAppleAccount() } }
                    .font(HeliTypography.actionButton(13))
                    .disabled(busy)
            }

            if !store.isManagedFamily || previewOnly {
                VStack(alignment: .leading, spacing: 10) {
                    Text(newUser ? "Create a family" : "Share your current family")
                        .font(HeliTypography.headline(17))
                        .foregroundColor(HeliColors.greenInk)
                    TextField("Family name", text: $familyName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.organizationName)
                    Button(newUser ? "Create family" : "Create and share this family") {
                        Task { await createFamily() }
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.cardWarmWhite)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(HeliColors.forestGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(previewOnly || busy || familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .disabled(previewOnly || busy || inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

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

    private func switchAppleAccount() async {
        busy = true
        defer { busy = false }
        do {
            try await api.logout()
            profile = nil
            nonce = nil
            await prepareChallenge()
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
                Text("They’ll sign in with Apple, enter this code, then choose their caregiver profile. The code works once and expires after seven days.")
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
