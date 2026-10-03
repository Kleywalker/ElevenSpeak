import Foundation

struct ElevenVoice: Codable, Identifiable, Hashable {
    let voice_id: String
    let name: String
    let description: String?
    let preview_url: String?

    var id: String { voice_id }
    var previewURL: URL? { preview_url.flatMap(URL.init) }
}

private struct VoicesResponse: Codable {
    let voices: [ElevenVoice]
}

enum ElevenLabsError: LocalizedError {
    case badResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Unexpected ElevenLabs response."
        case .api(let message):
            return "ElevenLabs: \(message)"
        }
    }
}

final class ElevenLabsClient {
    private let base = URL(string: "https://api.elevenlabs.io")!
    private let modelID = "eleven_multilingual_v2"
    private let outputFormat = "mp3_44100_128"

    func listVoices(apiKey: String) async throws -> [ElevenVoice] {
        var request = URLRequest(url: base.appendingPathComponent("v1/voices"))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data)
        return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
    }

    func streamRequest(
        text: String,
        voiceID: String,
        speed: Double,
        apiKey: String
    ) throws -> URLRequest {
        var components = URLComponents(
            url: base.appendingPathComponent("v1/text-to-speech/\(voiceID)/stream"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "output_format", value: outputFormat)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "speed": min(max(speed, 0.7), 1.2)
            ]
        ])
        return request
    }

    func synthesize(
        text: String,
        voiceID: String,
        speed: Double,
        apiKey: String
    ) async throws -> Data {
        let request = try streamRequest(
            text: text,
            voiceID: voiceID,
            speed: speed,
            apiKey: apiKey
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data)
        return data
    }

    private func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = object["detail"] as? [String: Any],
               let message = detail["message"] as? String {
                throw ElevenLabsError.api(message)
            }
            throw ElevenLabsError.api("HTTP \(http.statusCode)")
        }
    }
}
