import SwiftUI
@main struct ElevenSpeakApp:App{
 @StateObject private var app=AppModel()
 var body:some Scene{MenuBarExtra{MenuContent(app:app)}label:{Image(systemName:app.isSpeaking ? "speaker.wave.2.fill":"speaker.wave.2")}.menuBarExtraStyle(.menu)}
}
