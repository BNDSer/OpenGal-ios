import SwiftUI

struct CodeChatView: View {
    @StateObject private var vm: CodeViewModel
    @State private var showScrollToBottom = false
    @State private var scrollTrigger = false
    @State private var inputBarHeight: CGFloat = 100

    init(server: SSHServer, projectPath: String, sessionFile: String?) {
        _vm = StateObject(wrappedValue: CodeViewModel(
            server: server,
            projectPath: projectPath,
            sessionFile: sessionFile
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            messageList
                .overlay(alignment: .bottom) { inputArea }

            // Slash command popup
            if vm.inputText.hasPrefix("/") {
                VStack {
                    Spacer()
                    SlashCommandPopup(input: vm.inputText) { cmd in
                        vm.inputText = cmd + " "
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, inputBarHeight + 4)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(5)
            }

            // Approval overlay — glass panel above input bar
            if let prompt = vm.approvalPrompt {
                VStack {
                    Spacer()
                    ApprovalOverlay(
                        prompt: prompt,
                        onSelect: { option in
                            withAnimation(.spring(duration: 0.25)) {
                                vm.approve(option: option)
                            }
                        },
                        onInterrupt: {
                            withAnimation(.spring(duration: 0.25)) {
                                vm.approvalPrompt = nil
                                vm.interrupt()
                            }
                        }
                    )
                    .padding(.bottom, inputBarHeight + 8)
                }
                .background(Color.black.opacity(0.25).ignoresSafeArea())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(10)
                .animation(.spring(duration: 0.3), value: vm.approvalPrompt != nil)
            }
        }
        .navigationTitle(URL(fileURLWithPath: vm.projectPath).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { vm.startSession() }
        .onDisappear { vm.stopSession() }
        // Error alert
        .alert("错误", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        // Model picker sheet
        .sheet(isPresented: $vm.showModelPicker) {
            ModelPickerSheet { model in vm.switchModel(to: model) }
        }
        // Session picker sheet
        .sheet(isPresented: $vm.showSessionPicker) {
            SessionPickerSheet(sessions: vm.sessionFiles) { session in
                vm.resumeSession(session)
            }
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.messages) { msg in
                        codeBubble(msg)
                            .id(msg.id)
                            .padding(.vertical, 6)
                    }
                    if vm.isConnecting {
                        connectingIndicator
                    }
                    Color.clear.frame(height: inputBarHeight + 8)
                }
                .padding(.top, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
            } action: { _, dist in
                withAnimation(.easeOut(duration: 0.2)) {
                    showScrollToBottom = dist > 120
                }
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollTrigger) { _, _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func codeBubble(_ msg: CodeMessage) -> some View {
        if msg.role == .user {
            // Right-aligned grey pill — matches main chat MessageBubble
            HStack {
                Spacer(minLength: 60)
                Text(msg.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !msg.content.isEmpty {
                    Text(msg.content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                if !msg.diffBlocks.isEmpty {
                    DiffView(blocks: msg.diffBlocks)
                        .padding(.horizontal, 16)
                }
                if msg.isStreaming {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in BouncingDot(delay: Double(i) * 0.15) }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("正在连接 Claude Code…")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // Esc button — left side, only when TUI needs it
                if vm.needsEsc {
                    ZStack {
                        Color.clear.frame(width: 36, height: 36)
                            .glassEffect(.regular, in: Circle())
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            vm.sendEsc()
                        }) {
                            Text("Esc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .padding(.leading, 16)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                        .padding(.leading, 16)
                }

                Spacer()

                // Scroll-to-bottom button — right side
                if showScrollToBottom {
                    ZStack {
                        Color.clear.frame(width: 36, height: 36)
                            .glassEffect(.regular, in: Circle())
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            scrollTrigger.toggle()
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.trailing, 16)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                        .padding(.trailing, 16)
                }
            }
            .animation(.spring(duration: 0.2), value: vm.needsEsc)
            .animation(.easeOut(duration: 0.2), value: showScrollToBottom)
            .padding(.bottom, 4)

            CodeInputBar(
                text: $vm.inputText,
                mode: $vm.mode,
                isStreaming: vm.isStreaming,
                onSend: vm.sendMessage,
                onInterrupt: vm.interrupt
            )
        }
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { inputBarHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in inputBarHeight = h }
            }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(action: { vm.sendDirectCommand("/compact") }) {
                    Label("压缩上下文", systemImage: "arrow.down.to.line")
                }
                Button(action: { vm.sendDirectCommand("/status") }) {
                    Label("查看状态", systemImage: "info.circle")
                }
                Button(action: { vm.sendDirectCommand("/cost") }) {
                    Label("费用统计", systemImage: "dollarsign.circle")
                }
                Divider()
                Button(role: .destructive, action: { vm.sendDirectCommand("/clear") }) {
                    Label("清空对话", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        // Show interrupt button when Claude is actively responding
        if vm.isStreaming {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    vm.interrupt()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 18))
                }
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// BouncingDot reused from ChatView (redeclared here to avoid duplicate symbol)
private struct BouncingDot: View {
    let delay: Double
    @State private var up = false
    var body: some View {
        Circle().fill(Color(.systemGray3)).frame(width: 8, height: 8)
            .offset(y: up ? -5 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}
