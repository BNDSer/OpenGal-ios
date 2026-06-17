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
    private var currentTempURL: URL?   // temp file for non-favorited audio
    private var currentDelegate: TTSPlayerDelegate?

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

    // Fetch WAV data from TTS server. Returns nil on failure.
    func fetchAudio(text: String, config: TTSConfig) async -> Data? {
        guard config.enabled, !config.baseURL.isEmpty else { return nil }
        let urlString = config.baseURL.hasSuffix("/") ? config.baseURL + "tts" : config.baseURL + "/tts"
        guard let url = URL(string: urlString) else { return nil }

        let body: [String: Any] = [
            "text": text,
            "text_lang": "ja",
            "ref_audio_path": "/media/zichen/E/workspace/GPT-SoVITS/参考音频/yanami1.mp3",
            "prompt_text": "物申す必要が生じただけなの。ほら、うちのクラスのツワブキ祭の企画、準備が始まったでしょ?",
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

    // Play audio data for a message. Saves to temp file; deletes when done unless favorited.
    func play(data: Data, messageId: UUID, keepFile: Bool = false) {
        stopCurrent()

        var fileURL: URL
        if keepFile {
            fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        } else {
            fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(messageId.uuidString + ".wav")
            currentTempURL = fileURL
        }

        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL)
            }
            let p = try AVAudioPlayer(contentsOf: fileURL)
            let delegate = TTSPlayerDelegate.make(owner: self, messageId: messageId, isFavorited: keepFile)
            currentDelegate = delegate
            p.delegate = delegate
            p.play()
            player = p
            playingMessageId = messageId
        } catch {
            print("Audio playback error: \(error)")
        }
    }

    // Play a saved favorite audio file
    func playFavorite(messageId: UUID) {
        let fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        stopCurrent()
        do {
            let p = try AVAudioPlayer(contentsOf: fileURL)
            let delegate = TTSPlayerDelegate.make(owner: self, messageId: messageId, isFavorited: true)
            currentDelegate = delegate
            p.delegate = delegate
            p.play()
            player = p
            playingMessageId = messageId
        } catch {
            print("Favorite playback error: \(error)")
        }
    }

    // Save fetched audio data to favorites dir
    func saveFavoriteAudio(data: Data, messageId: UUID) {
        let fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        try? data.write(to: fileURL)
    }

    // Delete saved favorite audio
    func deleteFavoriteAudio(messageId: UUID) {
        let fileURL = Self.favoritesAudioDir.appendingPathComponent(messageId.uuidString + ".wav")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func stopCurrent() {
        player?.stop()
        player = nil
        playingMessageId = nil
        cleanupTempFile()
    }

    private func cleanupTempFile() {
        if let url = currentTempURL {
            try? FileManager.default.removeItem(at: url)
            currentTempURL = nil
        }
    }

    fileprivate func playerDidFinish(messageId: UUID, isFavorited: Bool) {
        if playingMessageId == messageId { playingMessageId = nil }
        if !isFavorited { cleanupTempFile() }
        player = nil
        currentDelegate = nil
    }
}

private final class TTSPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private weak var owner: TTSService?
    private let messageId: UUID
    private let isFavorited: Bool

    static func make(owner: TTSService, messageId: UUID, isFavorited: Bool) -> TTSPlayerDelegate {
        let d = TTSPlayerDelegate(owner: owner, messageId: messageId, isFavorited: isFavorited)
        return d
    }

    private init(owner: TTSService, messageId: UUID, isFavorited: Bool) {
        self.owner = owner
        self.messageId = messageId
        self.isFavorited = isFavorited
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let mid = messageId
        let fav = isFavorited
        Task { @MainActor [weak self] in
            self?.owner?.playerDidFinish(messageId: mid, isFavorited: fav)
        }
    }
}
