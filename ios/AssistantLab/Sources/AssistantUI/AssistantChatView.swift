import SwiftUI
import AssistantKit

/// The assistant surface.
///
/// Works either as a sheet or as a tab the host already owns the chrome for.
/// It holds no schedule state in either mode, so leaving it never disturbs the
/// week, filter or scroll position of the screen you came from.
public struct AssistantChatView: View {
    /// How the host is showing this.
    public enum Presentation: Sendable {
        /// Modal: the view supplies its own navigation bar and a Done button.
        case sheet
        /// A destination inside the host's own chrome. No navigation bar of
        /// its own, and extra bottom inset so the composer clears a floating
        /// tab bar.
        case embedded(bottomInset: CGFloat)
    }

    @ObservedObject private var model: AssistantChatModel
    private let presentation: Presentation
    private let onOpenEvent: (String, String) -> Void
    private let onDismiss: () -> Void

    @FocusState private var composerFocused: Bool
    @State private var showsClearConfirmation = false
    /// The unsent draft. Deliberately view-local: as `@Published` state on the
    /// model it re-rendered every message and card on each keystroke.
    @State private var draft = ""

    private var canSend: Bool {
        model.isIdle && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        model: AssistantChatModel,
        presentation: Presentation = .sheet,
        onOpenEvent: @escaping (String, String) -> Void = { _, _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.model = model
        self.presentation = presentation
        self.onOpenEvent = onOpenEvent
        self.onDismiss = onDismiss
    }

    private var isEmbedded: Bool {
        if case .embedded = presentation { return true }
        return false
    }

    private var bottomInset: CGFloat {
        if case .embedded(let inset) = presentation { return inset }
        return 0
    }

    public var body: some View {
        if isEmbedded {
            embeddedBody
        } else {
            sheetBody
        }
    }

    /// As a tab: the host draws the header, so this contributes only a compact
    /// title row and the conversation itself.
    private var embeddedBody: some View {
        ZStack {
            HeliColors.canvasIvory.ignoresSafeArea()
            VStack(spacing: 0) {
                embeddedHeader
                if model.showsDataDisclosure { disclosure } else { conversation }
            }
        }
        .confirmationDialog(
            "Clear this conversation?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { model.clearConversation() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Your schedule is not affected. Only the chat history on this device is removed.")
        }
    }

    /// Compact on purpose: the empty state and the conversation each carry
    /// their own heading, so a title here would be the second one on screen.
    private var embeddedHeader: some View {
        HStack(alignment: .center) {
            Eyebrow(text: "Assistant", color: HeliColors.mutedGray)
            Spacer(minLength: 8)
            Menu {
                Button(role: .destructive) { showsClearConfirmation = true } label: {
                    Label("Clear conversation", systemImage: "trash")
                }
            } label: {
                HeliIcon(name: "ellipsis", size: 15)
                    .foregroundStyle(HeliColors.forestGreen)
                    .frame(width: 36, height: 36)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HeliColors.sageRule, lineWidth: 0.8))
            }
            .accessibilityLabel("Conversation options")
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var sheetBody: some View {
        NavigationStack {
            ZStack {
                HeliColors.canvasIvory.ignoresSafeArea()
                if model.showsDataDisclosure {
                    disclosure
                } else {
                    conversation
                }
            }
            .navigationTitle("Assistant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HeliColors.canvasIvory, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                        .font(HeliTypography.actionButton(15))
                        .foregroundStyle(HeliColors.forestGreen)
                }
                ToolbarItem(placement: .principal) {
                    Text("Assistant")
                        .font(HeliTypography.serifTitle(18, weight: .medium))
                        .foregroundStyle(HeliColors.forestGreen)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showsClearConfirmation = true
                        } label: {
                            Label("Clear conversation", systemImage: "trash")
                        }
                    } label: {
                        HeliIcon(name: "ellipsis", size: 15)
                            .foregroundStyle(HeliColors.forestGreen)
                    }
                    .accessibilityLabel("Conversation options")
                }
            }
            .confirmationDialog(
                "Clear this conversation?",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) { model.clearConversation() }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Your schedule is not affected. Only the chat history on this device is removed.")
            }
        }
    }

    // MARK: - First use

    private var disclosure: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Before you start", color: HeliColors.sunOchre)
                    Text("What leaves this device")
                        .font(HeliTypography.serifTitle(26, weight: .medium))
                        .foregroundStyle(HeliColors.forestGreen)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HeliCard {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(AssistantCopy.help(.privacyAndData).body, id: \.self) { line in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(HeliColors.forestGreen.opacity(0.35))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(line)
                                    .font(HeliTypography.body(13.5))
                                    .foregroundStyle(HeliColors.greenInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                }

                Button("Got it") { model.acknowledgeDisclosure() }
                    .buttonStyle(HeliPrimaryButton())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.messages.isEmpty { emptyState }
                        ForEach(model.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if model.isWorking { workingRow.id(Self.workingAnchor) }
                        // Keeps the last card clear of the composer.
                        Color.clear.frame(height: 4).id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) { _, _ in scroll(proxy) }
                .onChange(of: model.isWorking) { _, _ in scroll(proxy) }
            }

            composer
        }
    }

    private static let bottomAnchor = "assistant.bottom"
    private static let workingAnchor = "assistant.working"

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask about your household's schedule.")
                    .font(HeliTypography.serifTitle(22, weight: .medium))
                    .foregroundStyle(HeliColors.forestGreen)
                    .fixedSize(horizontal: false, vertical: true)
                Text("I can only see this household \u{2014} its events, people and saved places.")
                    .font(HeliTypography.body(13))
                    .foregroundStyle(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Eyebrow(text: "Try")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.suggestedPrompts, id: \.self) { prompt in
                    Button { model.send(prompt) } label: {
                        HStack(spacing: 9) {
                            Text(prompt)
                                .font(HeliTypography.actionButton(13.5))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            HeliIcon(name: "arrow-up", size: 11)
                                .rotationEffect(.degrees(45))
                                .foregroundStyle(HeliColors.mutedGray)
                        }
                        .foregroundStyle(HeliColors.greenInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(HeliColors.sageRule.opacity(0.7), lineWidth: 0.8)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        ChatMessageRow(
            message: message,
            pendingProposalID: model.pendingProposalID,
            onOpenEvent: onOpenEvent,
            onConfirmProposal: { model.confirmPendingProposal() },
            onCancelProposal: { model.cancelPendingProposal() },
            onQuickReply: { model.send($0) }
        )
        .equatable()
    }

    private var workingRow: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .tint(HeliColors.forestGreen)
            Text("Working\u{2026}")
                .font(HeliTypography.caption(12))
                .foregroundStyle(HeliColors.mutedGray)
            Button("Stop") { model.cancel() }
                .font(HeliTypography.actionButton(12))
                .foregroundStyle(HeliColors.forestGreen)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HeliColors.cardWarmWhite)
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(HeliColors.sageRule.opacity(0.7), lineWidth: 0.8))
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(HeliColors.sageRule.opacity(0.8))
                .frame(height: 0.8)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your schedule", text: $draft, axis: .vertical)
                    .font(HeliTypography.body(14.5))
                    .foregroundStyle(HeliColors.greenInk)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(composerFocused ? HeliColors.forestGreen.opacity(0.5) : HeliColors.sageRule, lineWidth: 1)
                    )
                    #if os(iOS)
                    .submitLabel(.send)
                    #endif
                    .onSubmit { submit() }

                Button {
                    if model.isWorking { model.cancel() } else { submit() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(sendEnabled ? HeliColors.forestGreen : HeliColors.sageRule)
                            .frame(width: 38, height: 38)
                        HeliIcon(name: model.isWorking ? "stop" : "arrow-up", size: 14, weight: .bold)
                            .foregroundStyle(HeliColors.cardWarmWhite)
                    }
                }
                .disabled(!sendEnabled)
                .accessibilityLabel(model.isWorking ? "Stop" : "Send")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            // Clears the host's floating tab bar, which the content scrolls
            // underneath.
            .padding(.bottom, isEmbedded ? bottomInset : 8)
            .background(HeliColors.canvasIvory)
        }
    }

    private var sendEnabled: Bool { model.isWorking || canSend }

    private func submit() {
        let outgoing = draft
        guard !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        model.send(outgoing)
    }
}

/// One message, as its own view so SwiftUI can skip re-rendering it.
///
/// Kept `Equatable` on the message and the pending-review id alone: those are
/// the only inputs that change what it draws. Without this, appending one
/// message re-lays-out every card already on screen, which gets expensive once
/// a 30-occurrence review or a trend card is in the history.
struct ChatMessageRow: View, Equatable {
    let message: ChatMessage
    let pendingProposalID: String?
    var onOpenEvent: (String, String) -> Void
    var onConfirmProposal: () -> Void
    var onCancelProposal: () -> Void
    var onQuickReply: (String) -> Void

    static func == (lhs: ChatMessageRow, rhs: ChatMessageRow) -> Bool {
        lhs.message == rhs.message && lhs.pendingProposalID == rhs.pendingProposalID
    }

    var body: some View {
        switch message.author {
        case .user:
            HStack {
                Spacer(minLength: 44)
                Text(message.text ?? "")
                    .font(HeliTypography.body(14.5))
                    .foregroundStyle(HeliColors.cardWarmWhite)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(HeliColors.forestGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 11) {
                ForEach(message.cards) { card in
                    AssistantCardView(
                        card: card,
                        onOpenEvent: onOpenEvent,
                        onConfirmProposal: onConfirmProposal,
                        onCancelProposal: onCancelProposal,
                        onQuickReply: onQuickReply
                    )
                    // A review whose context has moved on cannot be applied:
                    // the buttons go inert and dim rather than failing later.
                    .disabled(isStale(card))
                    .opacity(isStale(card) ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isStale(_ card: AssistantCard) -> Bool {
        guard case .proposal(let proposal) = card else { return false }
        return pendingProposalID != proposal.proposalID
    }
}
