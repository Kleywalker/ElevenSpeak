import Foundation
import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var voices: [ElevenVoice] = []
    @Published var selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID") ?? ""
    @Published var speed = UserDefaults.standard.object(forKey: "speed") as? Double ?? 1.0
    @Published var isSpeaking = false
    @Published var status = "Ready"
    @Published var apiKey = ""
    @Published var launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
    @Published var hotKeyName = UserDefaults.standard.string(forKey: "hotKeyName") ?? GlobalHotKey.presets[0].displayName
    @Published var accessibilityTrusted = false
    @Published var streamingEnabled = UserDefaults.standard.object(forKey: "streamingEnabled") as? Bool ?? true

    private let eleven = ElevenLabsClient()
    private let textSource = SelectedTextService()
    private let player = AudioPlayer()
    private let streamingPlayer = StreamingAudioPlayer()
    private let hotKey = GlobalHotKey()

    init() {
        apiKey = KeychainStore.load() ?? ""
        accessibilityTrusted = textSource.hasAccessibilityPermission

        if let preset = GlobalHotKey.presets.first(where: { $0.displayName == hotKeyName }) {
            hotKey.register(preset) { [weak self] in
                Task { @MainActor in self?.toggleSpeak() }
            }
        }

        if launchAtLogin {
            setLaunchAtLogin(true, reportStatus: false)
        }

        Task { @MainActor in
            await refreshVoices()
        }
    }

    func saveAPIKey() {
        KeychainStore.save(apiKey)
        Task { @MainActor in
            await refreshVoices()
        }
    }

    func refreshVoices() async {
        guard !apiKey.isEmpty else {
            status = "Enter your ElevenLabs API key"
            return
        }

        do {
            voices = try await eleven.listVoices(apiKey: apiKey)
            if selectedVoiceID.isEmpty || !voices.contains(where: { $0.id == selectedVoiceID }) {
                selectedVoiceID = voices.first?.id ?? ""
            }
            UserDefaults.standard.set(selectedVoiceID, forKey: "selectedVoiceID")
            status = "\(voices.count) voices loaded"
        } catch {
            status = error.localizedDescription
        }
    }

    func toggleSpeak() {
        isSpeaking ? stop() : speakSelection()
    }

    func speakSelection() {
        Task { @MainActor in
            guard !apiKey.isEmpty else {
                status = "Set your ElevenLabs API key first"
                return
            }

            guard let voice = voices.first(where: { $0.id == selectedVoiceID }) ?? voices.first else {
                status = "No ElevenLabs voice selected"
                return
            }

            guard let text = await textSource.selectedText(),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                status = accessibilityTrusted
                    ? "No selected text found"
                    : "Allow ElevenSpeak in Accessibility settings first"
                return
            }

            isSpeaking = true
            status = streamingEnabled ? "Generating and streaming…" : "Generating…"

            do {
                if streamingEnabled {
                    let request = try eleven.streamRequest(
                        text: text,
                        voiceID: voice.id,
                        speed: speed,
                        apiKey: apiKey
                    )

                    try await streamingPlayer.start(request: request) { [weak self] in
                        Task { @MainActor in
                            self?.isSpeaking = false
                            self?.status = "Ready"
                        }
                    }
                } else {
                    let audio = try await eleven.synthesize(
                        text: text,
                        voiceID: voice.id,
                        speed: speed,
                        apiKey: apiKey
                    )
                    try player.play(data: audio) { [weak self] in
                        Task { @MainActor in
                            self?.isSpeaking = false
                            self?.status = "Ready"
                        }
                    }
                }

                if isSpeaking {
                    status = streamingEnabled ? "Speaking (streaming)" : "Speaking"
                }
            } catch {
                isSpeaking = false
                status = error.localizedDescription
            }
        }
    }

    func stop() {
        streamingPlayer.stop()
        player.stop()
        isSpeaking = false
        status = "Stopped"
    }

    func setSpeed(_ value: Double) {
        speed = value
        UserDefaults.standard.set(value, forKey: "speed")
    }

    func setStreaming(_ enabled: Bool) {
        streamingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "streamingEnabled")
    }

    func preview(_ voice: ElevenVoice) {
        guard let url = voice.previewURL else {
            status = "This voice has no preview"
            return
        }

        status = "Playing preview…"
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }
            Task { @MainActor in
                try? self?.player.play(data: data) { [weak self] in
                    Task { @MainActor in self?.status = "Ready" }
                }
            }
        }.resume()
    }

    func setHotKey(_ configuration: GlobalHotKey.Configuration) {
        hotKeyName = configuration.displayName
        UserDefaults.standard.set(configuration.displayName, forKey: "hotKeyName")
        hotKey.register(configuration) { [weak self] in
            Task { @MainActor in self?.toggleSpeak() }
        }
        status = "Hotkey: \(configuration.displayName)"
    }

    func setLaunchAtLogin(_ enabled: Bool, reportStatus: Bool = true) {
        launchAtLogin = enabled
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            if reportStatus {
                status = enabled ? "Launch at login enabled" : "Launch at login disabled"
            }
        } catch {
            status = "Login item: \(error.localizedDescription)"
        }
    }

    func requestAccessibility() {
        textSource.requestAccessibilityPermission()
        refreshAccessibilityStatus()
        status = accessibilityTrusted
            ? "Accessibility access is enabled"
            : "Allow ElevenSpeak in System Settings → Privacy & Security → Accessibility"
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = textSource.hasAccessibilityPermission
    }
}
