import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @ObservedObject private var store = ConversationStore.shared
    @ObservedObject private var tts = TTSService.shared
    @ObservedObject private var settings = AppSettings.shared

    private var preferredScheme: ColorScheme? {
        switch settings.colorScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    @State private var showSettings = false
    @State private var showSidebar = false
    @State private var dragOffset: CGFloat = 0
    @State private var showFavorites = false
    @State private var showCode = false
    @State private var inputBarHeight: CGFloat = 80

    // Attachment state — lives here so + button can be in toolbar
    @State private var showAttachmentMenu = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var showCamera = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

    @State private var showScrollToBottom = false
    @State private var scrollToBottomTrigger = false

    var body: some View {
        // slideAmount: how far main panel moves right. Screen width - this = visible sliver.
        // sidebarWidth matches the sliver so sidebar content aligns perfectly.
        let screenWidth = UIScreen.main.bounds.width
        let slideAmount: CGFloat = screenWidth * 0.72
        let sidebarWidth: CGFloat = slideAmount

        // Live offset: base + finger drag, clamped to [0, slideAmount]
        let currentOffset: CGFloat = (showSidebar ? slideAmount : 0) + dragOffset
        let clampedOffset = max(0, min(slideAmount, currentOffset))
        let progress = clampedOffset / slideAmount  // 0 = closed, 1 = open

        ZStack(alignment: .leading) {
            // Bottom layer: sidebar, fixed width = slideAmount so it aligns with revealed area
            SidebarView(
                store: store,
                showFavorites: $showFavorites,
                onNewChat: { store.newConversation(); closeSidebar() },
                onCode: { closeSidebar(); showCode = true },
                onSelect: { id in store.select(id); closeSidebar() }
            )
            .frame(width: sidebarWidth)
            .background(Color(.systemBackground))
            .ignoresSafeArea()

            // Top layer: NavigationStack slides right. Settings push inside is unaffected.
            NavigationStack {
                mainChatView
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 62 * progress,   // left corners get the radius
                    bottomLeadingRadius: 62 * progress,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.2 * progress), radius: 20, x: -4, y: 0)
            .offset(x: clampedOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .onChanged { v in
                        let dx = v.translation.width
                        let dy = v.translation.height
                        guard abs(dx) > abs(dy) else { return }
                        guard !showSettings else { return }
                        guard !WebScrollState.shared.isOverScrollable else { return }
                        if !showSidebar && dx > 0 {
                            dragOffset = dx
                        } else if showSidebar && dx < 0 {
                            dragOffset = dx
                        }
                    }
                    .onEnded { v in
                        let dx = v.translation.width
                        let dy = v.translation.height
                        guard abs(dx) > abs(dy) else {
                            withAnimation(.spring(duration: 0.3, bounce: 0.05)) { dragOffset = 0 }
                            return
                        }
                        guard !showSettings else {
                            withAnimation(.spring(duration: 0.3, bounce: 0.05)) { dragOffset = 0 }
                            return
                        }
                        guard !WebScrollState.shared.isOverScrollable else {
                            withAnimation(.spring(duration: 0.3, bounce: 0.05)) { dragOffset = 0 }
                            return
                        }
                        let velocity = v.predictedEndTranslation.width - dx
                        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                            if !showSidebar {
                                showSidebar = dx + velocity > slideAmount * 0.3
                            } else {
                                showSidebar = !((-dx - velocity) > slideAmount * 0.3)
                            }
                            dragOffset = 0
                        }
                    }
            )
            .overlay {
                if showSidebar {
                    // Sliver on the right: tap or left-swipe to close sidebar
                    HStack(spacing: 0) {
                        Color.clear.frame(width: slideAmount)
                        Color.black.opacity(0.01)
                            .contentShape(Rectangle())
                            .onTapGesture { closeSidebar() }
                            .gesture(
                                DragGesture(minimumDistance: 10)
                                    .onChanged { v in
                                        let dx = v.translation.width
                                        let dy = v.translation.height
                                        guard abs(dx) > abs(dy), dx < 0 else { return }
                                        dragOffset = dx
                                    }
                                    .onEnded { v in
                                        let dx = v.translation.width
                                        let velocity = v.predictedEndTranslation.width - dx
                                        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                                            showSidebar = !((-dx - velocity) > slideAmount * 0.3)
                                            dragOffset = 0
                                        }
                                    }
                            )
                    }
                    .ignoresSafeArea()
                }
            }
            .zIndex(1)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showFavorites) {
            NavigationStack {
                FavoritesView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showFavorites = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showCode) {
            CodeEntryView()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems,
                      maxSelectionCount: 5, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            let captured = items; photoPickerItems = []
            Task { for item in captured { await loadPhoto(item) } }
        }
        .fileImporter(isPresented: $showDocumentPicker,
                      allowedContentTypes: [.pdf, .plainText, .image, .jpeg, .png],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await loadFiles(urls) } }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                guard let raw = image.jpegData(compressionQuality: 1.0) else { return }
                let data = forceCompress(raw)
                viewModel.pendingAttachments.append(MessageAttachment(
                    filename: "photo.jpg", mimeType: "image/jpeg",
                    base64Data: data.base64EncodedString()))
            }
        }
        .alert("错误", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        ), actions: {
            Button("好", role: .cancel) { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "")
        })
        .onChange(of: store.activeId) { _, _ in viewModel.stopTTS() }
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - Attachment menu card

    private var mainChatView: some View {
        ZStack(alignment: .bottom) {
            messageList
                .overlay(alignment: .bottom) { inputBarArea }

            if showAttachmentMenu {
                attachmentMenu
                    .padding(.bottom, inputBarHeight + 8)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .navigationTitle(store.active?.title ?? "OpenGal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if showAttachmentMenu {
                    withAnimation(.spring(duration: 0.25)) { showAttachmentMenu = false }
                }
            }
        )
    }

    // MARK: - Attachment menu

    private var attachmentMenu: some View {
        VStack(spacing: 0) {
            menuRow(icon: "camera.fill", label: "相机") {
                withAnimation(.spring(duration: 0.25)) { showAttachmentMenu = false }
                showCamera = true
            }
            Divider().padding(.leading, 54)
            menuRow(icon: "photo.fill", label: "照片") {
                withAnimation(.spring(duration: 0.25)) { showAttachmentMenu = false }
                showPhotoPicker = true
            }
            Divider().padding(.leading, 54)
            menuRow(icon: "paperclip", label: "文件") {
                withAnimation(.spring(duration: 0.25)) { showAttachmentMenu = false }
                showDocumentPicker = true
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func menuRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(.systemGray5)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.primary)
                }
                Text(label).font(.body).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private func closeSidebar() {
        dismissKeyboard()
        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
            showSidebar = false
            dragOffset = 0
        }
    }

    // MARK: - Input bar

    private var inputBarArea: some View {
        VStack(spacing: 0) {
            // Scroll-to-bottom button
            if showScrollToBottom {
                HStack {
                    Spacer()
                    ZStack {
                        Color.clear
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular, in: Circle())
                        Button(action: { haptic(); scrollToBottomTrigger.toggle() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .padding(.bottom, 4)
            }

            ChatInputBar(
                text: $viewModel.inputText,
                attachments: $viewModel.pendingAttachments,
                isLoading: viewModel.isLoading,
                isDisabled: store.active?.mode == .unset,
                onSend: viewModel.sendMessage,
                onCancel: viewModel.cancelRequest,
                onAttach: {
                    withAnimation(.spring(duration: 0.25)) { showAttachmentMenu.toggle() }
                }
            )
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { inputBarHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in inputBarHeight = h }
            }
        )
    }

    // MARK: - Toolbar

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: {
                haptic()
                dismissKeyboard()
                withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                    showSidebar.toggle()
                    dragOffset = 0
                }
            }) {
                Image(systemName: "sidebar.left")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if tts.playingMessageId != nil {
                Button(action: viewModel.stopTTS) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                }
            }
            Button(action: { haptic(); showSettings = true }) {
                Image(systemName: "gear")
            }
            Button(action: { haptic(); store.newConversation() }) {
                Image(systemName: "square.and.pencil")
            }
        }
    }

    // MARK: - Message list

    private var isGalMode: Bool { store.active?.mode == .gal }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.active?.mode == .unset && viewModel.messages.isEmpty {
                        ModePickerView { mode in store.setMode(mode) }
                            .id("modePicker")
                    }
                    ForEach(viewModel.messages) { msg in
                        MessageBubble(
                            message: msg,
                            showPlayButton: isGalMode,
                            onPlay: {
                                if tts.playingMessageId == msg.id { viewModel.stopTTS() }
                                else { viewModel.playMessage(msg) }
                            },
                            onFavorite: { viewModel.toggleFavorite(msg) }
                        )
                        .id(msg.id)
                        .padding(.vertical, 6)
                    }
                    if viewModel.isLoading { loadingIndicator }
                    // Spacer so last message isn't hidden behind input bar
                    Color.clear.frame(height: inputBarHeight + 8)
                }
                .padding(.top, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissKeyboard() }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
            } action: { _, distanceFromBottom in
                withAnimation(.easeOut(duration: 0.2)) {
                    showScrollToBottom = distanceFromBottom > 120
                }
            }
            .onChange(of: scrollToBottomTrigger) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.activeId) { _, _ in
                let target = viewModel.messages.last(where: { $0.role == .user })?.id
                    ?? viewModel.messages.last?.id
                if let id = target {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    private var loadingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in BouncingDot(delay: Double(i) * 0.15) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - File loaders

    private static let maxImageBytes = 3_700_000  // base64 adds ~33%; 3.7MB * 1.33 ≈ 4.9MB, safely under API 5MB limit

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let finalData = forceCompress(data)
        let att = MessageAttachment(filename: "image.jpg", mimeType: "image/jpeg",
                                    base64Data: finalData.base64EncodedString())
        await MainActor.run { viewModel.pendingAttachments.append(att) }
    }

    private func loadFiles(_ urls: [URL]) async {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard var data = try? Data(contentsOf: url) else { continue }
            var mime = mimeType(for: url)
            if mime.hasPrefix("image/") { data = forceCompress(data); mime = "image/jpeg" }
            let att = MessageAttachment(filename: url.lastPathComponent, mimeType: mime,
                                        base64Data: data.base64EncodedString())
            await MainActor.run { viewModel.pendingAttachments.append(att) }
        }
    }

    // Always converts to JPEG and compresses until under maxImageBytes.
    private func forceCompress(_ data: Data) -> Data {
        guard let src = UIImage(data: data) else { return data }
        let limit = Self.maxImageBytes

        // Normalise orientation and colour space by redrawing into a fresh bitmap
        func redraw(_ image: UIImage, scale: CGFloat = 1.0) -> UIImage {
            let sz = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            return UIGraphicsImageRenderer(size: sz, format: fmt).image { _ in
                image.draw(in: CGRect(origin: .zero, size: sz))
            }
        }

        // Phase 1: quality reduction on full-size redrawn image
        let full = redraw(src)
        var quality: CGFloat = 0.85
        while quality >= 0.05 {
            if let out = full.jpegData(compressionQuality: quality), out.count <= limit {
                return out
            }
            quality -= 0.1
        }

        // Phase 2: scale down until it fits
        var scale: CGFloat = 0.7
        while scale > 0.05 {
            let small = redraw(src, scale: scale)
            if let out = small.jpegData(compressionQuality: 0.8), out.count <= limit {
                return out
            }
            scale -= 0.15
        }

        // Absolute fallback: cap longest edge at 1024px
        let maxEdge: CGFloat = 1024
        let ratio = min(maxEdge / src.size.width, maxEdge / src.size.height, 1)
        let tiny = redraw(src, scale: ratio)
        return tiny.jpegData(compressionQuality: 0.7) ?? data
    }

    private func compressedImageData(_ data: Data) -> (Data, String) {
        return (forceCompress(data), "image/jpeg")
    }

    private func mimeType(for url: URL) -> String {
        guard let uti = UTType(filenameExtension: url.pathExtension) else { return "application/octet-stream" }
        if uti.conforms(to: .jpeg)      { return "image/jpeg" }
        if uti.conforms(to: .png)       { return "image/png" }
        if uti.conforms(to: .gif)       { return "image/gif" }
        if uti.conforms(to: .pdf)       { return "application/pdf" }
        if uti.conforms(to: .plainText) { return "text/plain" }
        return "application/octet-stream"
    }
}

private struct BouncingDot: View {
    let delay: Double
    @State private var up = false
    var body: some View {
        Circle().fill(Color(.systemGray3)).frame(width: 8, height: 8)
            .offset(y: up ? -5 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) { up = true }
            }
    }
}

// MARK: - Camera picker

struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = .camera; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { parent.onCapture(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}
