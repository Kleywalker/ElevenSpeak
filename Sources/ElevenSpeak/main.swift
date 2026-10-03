import SwiftUI
import AppKit

@main
struct ElevenSpeakApp: App {
    var body: some Scene {
        MenuBarExtra("ElevenSpeak", systemImage: "waveform.and.mic") {
            Text("ElevenSpeak")
                .font(.headline)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
