import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject var app: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(app.isSpeaking ? "Stop speaking" : "Read selected text") {
                app.toggleSpeak()
            }

            Divider()

            Text(app.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !app.voices.isEmpty {
                Menu("Voice") {
                    ForEach(app.voices) { voice in
                        Button {
                            app.selectedVoiceID = voice.id
                            UserDefaults.standard.set(voice.id, forKey: "selectedVoiceID")
                        } label: {
                            HStack {
                                Text(voice.name)
                                if voice.id == app.selectedVoiceID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Button("Preview") {
                            app.preview(voice)
                        }
                    }
                }
            }

            Menu("Speed") {
                ForEach([0.7, 0.8, 0.9, 1.0, 1.1, 1.2], id: \.self) { value in
                    Button(String(format: "%.1fx", value)) {
                        app.setSpeed(value)
                    }
                }
            }

            Divider()

            Button("Settings…") {
                showingSettings = true
            }

            Button("Quit ElevenSpeak") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .sheet(isPresented: $showingSettings) {
            SettingsView(app: app)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ElevenSpeak")
                .font(.title2.bold())

            Text("ElevenLabs API key")
                .font(.headline)

            SecureField("xi-api-key", text: $key)
                .textFieldStyle(.roundedBorder)

            Text("The key is stored in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Global hotkey", selection: Binding(
                get: { app.hotKeyName },
                set: { name in
                    if let preset = GlobalHotKey.presets.first(where: { $0.displayName == name }) {
                        app.setHotKey(preset)
                    }
                }
            )) {
                ForEach(GlobalHotKey.presets, id: \.displayName) { preset in
                    Text(preset.displayName).tag(preset.displayName)
                }
            }

            Toggle(
                "Stream audio while generating",
                isOn: Binding(
                    get: { app.streamingEnabled },
                    set: { app.setStreaming($0) }
                )
            )

            Toggle(
                "Launch ElevenSpeak at login",
                isOn: Binding(
                    get: { app.launchAtLogin },
                    set: { app.setLaunchAtLogin($0) }
                )
            )

            HStack {
                Text("Accessibility")
                Spacer()
                Text(app.accessibilityTrusted ? "Enabled" : "Required")
                    .foregroundStyle(app.accessibilityTrusted ? .green : .orange)
            }

            Button("Open Accessibility Settings") {
                app.requestAccessibility()
            }

            HStack {
                Button("Save & Load Voices") {
                    app.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    app.saveAPIKey()
                }
                .keyboardShortcut(.defaultAction)

                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            key = app.apiKey
            app.refreshAccessibilityStatus()
        }
    }
}
