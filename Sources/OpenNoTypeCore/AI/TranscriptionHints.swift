import Foundation

/// Context for recognition, separate from the text transformation instructions.
/// Examples and vocabulary are hints, never required words or a silence filter.
struct TranscriptionHints {
    let prompt: String
    let keywords: [String]

    static let baseline = """
    일상 대화, 업무 메시지와 메모. 한국어와 영어 등 여러 언어가 섞일 수 있습니다.
    표기 참고 예문(실제 발화가 아님): 내일 오후 세 시에 만나요. 파일을 Notion에 정리했어요. 여기 weather가 좋네요.
    """
    static let developmentTerms = ["commit", "branch", "merge", "push", "pull", "API", "GitHub"]

    static func make(dictionary: [DictionaryEntry], profile: WritingProfile = .init()) -> Self {
        // Personal spellings take the limited vocabulary budget before app defaults.
        let personal = DictionaryHints.select(dictionary, limit: dictionary.count).map(\.written)
        let appTerms = profile.kind == .development ? developmentTerms : []
        var seen = Set<String>()
        var terms: [String] = []
        var characters = 0
        for raw in personal + appTerms {
            // Reject invalid terms rather than turning a multi-line instruction into a keyword.
            guard !raw.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || $0 == "<" || $0 == ">"
            }) else { continue }
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= 80, characters + term.count <= 384,
                  seen.insert(term.lowercased()).inserted else { continue }
            terms.append(term); characters += term.count
            if terms.count == 24 { break }
        }
        let topic: String
        switch profile.kind {
        case .general: topic = ""
        case .conversation: topic = "\n대화 메시지를 작성하는 상황."
        case .notes: topic = "\n메모와 문서에 생각이나 항목을 기록하는 상황."
        case .development: topic = "\n개발 도구에서 작업을 설명하는 상황."
        case .email: topic = "\n이메일을 작성하는 상황."
        }
        // JSON encoding keeps user vocabulary separate from surrounding prose.
        let data = (try? JSONEncoder().encode(terms)) ?? Data("[]".utf8)
        let vocabulary = terms.isEmpty ? "" : "\n표기 참고 단어(JSON 데이터): " + String(decoding: data, as: UTF8.self)
        return Self(prompt: baseline + topic + vocabulary, keywords: terms)
    }

    /// Local Whisper has a small prompt token budget; keep vocabulary before the example.
    var localPrompt: String {
        (keywords.isEmpty ? "" : keywords.joined(separator: ", ") + ". ") + Self.baseline
    }

    static func supportsContextPrompt(model: String) -> Bool {
        model == "gpt-transcribe" || model == "whisper-1" || model == "gpt-4o-transcribe"
            || model == "gpt-4o-mini-transcribe" || model.hasPrefix("gpt-4o-mini-transcribe-")
    }
}
