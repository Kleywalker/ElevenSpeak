import Foundation
struct ElevenVoice:Codable,Identifiable,Hashable{let voice_id:String;let name:String;let description:String?;let preview_url:String?;var id:String{voice_id};var previewURL:URL?{preview_url.flatMap(URL.init)}}
private struct VoicesResponse:Codable{let voices:[ElevenVoice]}
enum ElevenLabsError:LocalizedError{case badResponse,api(String);var errorDescription:String?{switch self{case .badResponse:return"Unexpected ElevenLabs response.";case .api(let m):return"ElevenLabs: \\(m)"}}}
final class ElevenLabsClient{
 private let base=URL(string:"https://api.elevenlabs.io")!
 func listVoices(apiKey:String)async throws->[ElevenVoice]{var r=URLRequest(url:base.appendingPathComponent("v1/voices"));r.setValue(apiKey,forHTTPHeaderField:"xi-api-key");let(d,res)=try await URLSession.shared.data(for:r);try validate(res,d);return try JSONDecoder().decode(VoicesResponse.self,from:d).voices}
 func synthesize(text:String,voiceID:String,speed:Double,apiKey:String)async throws->Data{var c=URLComponents(url:base.appendingPathComponent("v1/text-to-speech/\\(voiceID)/stream"),resolvingAgainstBaseURL:false)!;c.queryItems=[URLQueryItem(name:"output_format",value:"mp3_44100_128")];var r=URLRequest(url:c.url!);r.httpMethod="POST";r.setValue(apiKey,forHTTPHeaderField:"xi-api-key");r.setValue("application/json",forHTTPHeaderField:"Content-Type");r.httpBody=try JSONSerialization.data(withJSONObject:["text":text,"model_id":"eleven_multilingual_v2","voice_settings":["speed":min(max(speed,0.7),1.2)]]);let(d,res)=try await URLSession.shared.data(for:r);try validate(res,d);return d}
 private func validate(_ res:URLResponse,_ data:Data)throws{guard let h=res as?HTTPURLResponse else{throw ElevenLabsError.badResponse};guard(200..<300).contains(h.statusCode)else{if let o=try?JSONSerialization.jsonObject(with:data)as?[String:Any],let det=o["detail"]as?[String:Any],let m=det["message"]as?String{throw ElevenLabsError.api(m)};throw ElevenLabsError.api("HTTP \\(h.statusCode)")}}
}
