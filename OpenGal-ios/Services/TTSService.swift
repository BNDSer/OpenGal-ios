import Foundation
import Combine
import AVFoundation

@MainActor
final class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()

    @Published var playingMessageId: UUID? = nil

    // Directories
    static var favoritesAudioDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("FavoriteAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var player: AVAudioPlayer?
    private var currentTempURL: URL?
    private var currentDelegate: TTSPlayerDelegate?
    // Track whether the currently-playing message has been favorited mid-playback
    private var currentIsFavorited: Bool = false

    private override init() {
        super.init()
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // Fetch WAV data from TTS server. Runs off MainActor to avoid blocking UI.
    nonisolated func fetchAudio(text: String, config: TTSConfig) async -> Data? {
        guard config.enabled, !config.baseURL.isEmpty else { return nil }
        let urlString = config.baseURL.hasSuffix("/") ? config.baseURL + "tts" : config.baseURL + "/tts"
        guard let url = URL(string: urlString) else { return nil }

        let (refAudio, promptText): (String, String)
        switch config.character {
        case "megumi":
            refAudio = "/media/zichen/E/workspace/GPT-SoVITS/参考音频/megumi.mp3"
            promptText = "あなたは、私の1番大事なお友達だから"
        case "ling":
            refAudio = "/media/zichen/E/workspace/GPT-SoVITS/参考音频/ling1.mp3"
            promptText = "お兄ちゃん、何かあったの?ねー、これだと私たちの会話、あいつに丸聞こえなんじゃないかな"
        default:
            refAudio = "/media/zichen/E/workspace/GPT-SoVITS/参考音频/yanami1.mp3"
            promptText = "物申す必要が生じただけなの。ほら、うちのクラスのツワブキ祭の企画、準備が始まったでしょ?"
        }

        let body: [String: Any] = [
            "text": text,
            "text_lang": "ja",
            "ref_audio_path": refAudio,
            "prompt_text": promptText,
            "prompt_lang": "ja",
            "top_k": 15,
            "top_p": 1,
            "temperature": 1,
            "text_split_method": "cut0",
            "media_type": "wav"
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return data
        } catch {
            print("TTS fetch failed: \(error)")
            return nil
        }
    }

    // Play audio data. keepFile=true saves to favorites dir permanently.
    func play(data: Data, messageId: UUID, keepFile: Bool = false) {
        stopCurrent()

        let fileURL: URL
        if keepFile {
            fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        } else {
            fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(messageId.uuidString + ".wav")
            currentTempURL = fileURL
        }
        currentIsFavorited = keepFile

        do {
            // Always write fresh — avoids stale-file issues
            try data.write(to: fileURL, options: .atomic)
            let p = try AVAudioPlayer(contentsOf: fileURL)
            let delegate = TTSPlayerDelegate(owner: self, messageId: messageId)
            currentDelegate = delegate
            p.delegate = delegate
            p.play()
            player = p
            playingMessageId = messageId
        } catch {
            print("Audio playback error: \(error)")
            currentTempURL = nil
            currentIsFavorited = false
        }
    }

    // Play a saved favorite audio file
    func playFavorite(messageId: UUID) {
        let fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        stopCurrent()
        do {
            let p = try AVAudioPlayer(contentsOf: fileURL)
            currentIsFavorited = true
            let delegate = TTSPlayerDelegate(owner: self, messageId: messageId)
            currentDelegate = delegate
            p.delegate = delegate
            p.play()
            player = p
            playingMessageId = messageId
        } catch {
            print("Favorite playback error: \(error)")
        }
    }

    // Called when a playing message gets favorited mid-playback.
    // Updates state so the temp file won't be deleted when playback ends.
    func markCurrentAsFavorited(messageId: UUID, data: Data) {
        guard playingMessageId == messageId else { return }
        // Save data to favorites dir
        let favURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        try? data.write(to: favURL, options: .atomic)
        // Stop deleting the temp file on finish
        currentIsFavorited = true
        // Clear temp file reference so cleanupTempFile won't touch it
        currentTempURL = nil
    }

    // Save fetched audio data to favorites dir (called when message is not currently playing)
    func saveFavoriteAudio(data: Data, messageId: UUID) {
        let fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        try? data.write(to: fileURL, options: .atomic)
    }

    // Delete saved favorite audio
    func deleteFavoriteAudio(messageId: UUID) {
        // Don't delete while we're playing it
        if playingMessageId == messageId {
            stopCurrent()
        }
        let fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func stopCurrent() {
        player?.stop()
        player = nil
        playingMessageId = nil
        currentDelegate = nil
        if !currentIsFavorited { cleanupTempFile() }
        currentIsFavorited = false
    }

    private func cleanupTempFile() {
        if let url = currentTempURL {
            try? FileManager.default.removeItem(at: url)
            currentTempURL = nil
        }
    }

    fileprivate func playerDidFinish(messageId: UUID) {
        guard playingMessageId == messageId else { return }
        playingMessageId = nil
        if !currentIsFavorited { cleanupTempFile() }
        currentIsFavorited = false
        player = nil
        currentDelegate = nil
    }
}

private final class TTSPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private weak var owner: TTSService?
    private let messageId: UUID

    init(owner: TTSService, messageId: UUID) {
        self.owner = owner
        self.messageId = messageId
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let mid = messageId
        Task { @MainActor [weak self] in
            self?.owner?.playerDidFinish(messageId: mid)
        }
    }
}
