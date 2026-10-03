import Foundation
import AppKit
import Combine
@MainActor final class AppModel:ObservableObject{
 @Published var voices:[ElevenVoice]=[]
 @Published var selectedVoiceID=UserDefaults.standard.string(forKey:"selectedVoiceID") ?? ""
 @Published var speed=UserDefaults.standard.object(forKey:"speed") as? Double ?? 1.0
 @Published var isSpeaking=false
 @Published var status="Ready"
 @Published var apiKey=""
 private let eleven=ElevenLabsClient(),textSource=SelectedTextService(),player=AudioPlayer(),hotKey=GlobalHotKey()
 init(){apiKey=KeychainStore.load() ?? "";hotKey.registerOptionEscape{[weak self]in DispatchQueue.main.async{self?.toggleSpeak()}};Task{await refreshVoices()}}
 func saveAPIKey(){KeychainStore.save(apiKey);Task{await refreshVoices()}}
 func refreshVoices()async{guard !apiKey.isEmpty else{status="Enter your ElevenLabs API key";return};do{voices=try await eleven.listVoices(apiKey:apiKey);if selectedVoiceID.isEmpty{selectedVoiceID=voices.first?.id ?? ""};UserDefaults.standard.set(selectedVoiceID,forKey:"selectedVoiceID");status="\\(voices.count) voices loaded"}catch{status=error.localizedDescription}}
 func toggleSpeak(){isSpeaking ? stop():speakSelection()}
 func speakSelection(){Task{guard !apiKey.isEmpty else{status="Set your ElevenLabs API key first";return};guard let voice=voices.first(where:{$0.id==selectedVoiceID}) ?? voices.first else{status="No ElevenLabs voice selected";return};guard let text=await textSource.selectedText(),!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{status="No selected text found";return};isSpeaking=true;status="Generating…";do{let audio=try await eleven.synthesize(text:text,voiceID:voice.id,speed:speed,apiKey:apiKey);try player.play(data:audio){[weak self]in DispatchQueue.main.async{self?.isSpeaking=false;self?.status="Ready"}};status="Speaking"}catch{isSpeaking=false;status=error.localizedDescription}}}
 func stop(){player.stop();isSpeaking=false;status="Stopped"}
 func setSpeed(_ v:Double){speed=v;UserDefaults.standard.set(v,forKey:"speed")}
 func preview(_ voice:ElevenVoice){guard let url=voice.previewURL else{return};URLSession.shared.dataTask(with:url){[weak self]d,_,_ in guard let d else{return};try? self?.player.play(data:d,completion:nil)}.resume()}
}
