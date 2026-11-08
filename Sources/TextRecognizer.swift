import Foundation
import Vision

/// On-device text recognition (Apple Vision). Nothing leaves the Mac.
enum TextRecognizer {
    static func recognize(_ url: URL, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            // Prefer the user's own languages (e.g. Russian) alongside English.
            if let supported = try? request.supportedRecognitionLanguages() {
                var languages: [String] = []
                for preferred in Locale.preferredLanguages + ["en-US"] {
                    let code = preferred.prefix(2)
                    if let match = supported.first(where: { $0.hasPrefix(code) }), !languages.contains(match) {
                        languages.append(match)
                    }
                }
                if !languages.isEmpty { request.recognitionLanguages = languages }
            }

            try? VNImageRequestHandler(url: url).perform([request])
            let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
    }
}
