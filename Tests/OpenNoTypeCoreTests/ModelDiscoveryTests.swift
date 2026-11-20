import XCTest
@testable import OpenNoTypeCore

final class ModelDiscoveryTests: XCTestCase {
    func testOpenRouterKeepsPaidStructuredTextModelsWithPrices() throws {
        let json = """
        {"data":[
          {"id":"vendor/good","name":"Good","pricing":{"prompt":"0.0000001","completion":"0.0000005"},
           "architecture":{"input_modalities":["text"],"output_modalities":["text"]},"supported_parameters":["structured_outputs","max_tokens"]},
          {"id":"vendor/good:free","pricing":{"prompt":"0","completion":"0"},"supported_parameters":["structured_outputs"]},
          {"id":"vendor/good:batch","pricing":{"prompt":"0.00000005","completion":"0.00000025"},"supported_parameters":["structured_outputs"]},
          {"id":"openrouter/auto","pricing":{"prompt":"-1","completion":"-1"},"supported_parameters":["structured_outputs"]},
          {"id":"vendor/no-json","pricing":{"prompt":"0.000001","completion":"0.000001"},"supported_parameters":["max_tokens"]},
          {"id":"vendor/image","pricing":{"prompt":"0.000001","completion":"0.000001"},
           "architecture":{"input_modalities":["text"],"output_modalities":["image"]},"supported_parameters":["response_format"]}
        ]}
        """
        let models = try ModelDiscovery.parseOpenRouter(Data(json.utf8))
        XCTAssertEqual(models.map(\.modelID), ["vendor/good"])
        XCTAssertEqual(models.first?.inputUSDPerMillion ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(models.first?.outputUSDPerMillion ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(models.first?.kind, .text)
    }

    func testModelIDListsClassifyTextAndSpeechAndSkipInactiveOrUnsupported() throws {
        let json = #"{"data":[{"id":"gpt-7-mini"},{"id":"o5"},{"id":"gpt-transcribe-2"},{"id":"text-embedding-4"},{"id":"gpt-realtime"},{"id":"tts-2"}]}"#
        let openAI = try ModelDiscovery.parseModelIDs(Data(json.utf8), provider: .openAI)
        XCTAssertEqual(openAI.map(\.modelID), ["gpt-7-mini", "o5", "gpt-transcribe-2"])
        XCTAssertEqual(openAI.last?.kind, .speech)
        let groq = try ModelDiscovery.parseModelIDs(Data(#"{"data":[{"id":"llama-5","active":true},{"id":"old","active":false},{"id":"whisper-large-v4","active":true},{"id":"llama-guard-4","active":true}]}"#.utf8), provider: .groq)
        XCTAssertEqual(groq.map(\.modelID), ["llama-5", "whisper-large-v4"])
        XCTAssertNil(ModelDiscovery.classify("whisper-1", provider: .anthropic))
        XCTAssertEqual(ModelDiscovery.classify("claude-sonnet-6", provider: .anthropic), .text)
    }

    func testFirstSearchIsABaselineAndLaterSearchesMarkOnlyUnseenNonCatalogModels() {
        let first = [DiscoveredModel(provider: .groq, modelID: "a", kind: .text), DiscoveredModel(provider: .groq, modelID: "b", kind: .text)]
        let baseline = ModelDiscovery.merge(previous: [], fetched: first, provider: .groq, catalogIDs: [], isFirstSearch: true)
        XCTAssertFalse(baseline.contains { $0.isNew })
        let second = first + [DiscoveredModel(provider: .groq, modelID: "c", kind: .text), DiscoveredModel(provider: .groq, modelID: "catalog", kind: .text)]
        let other = DiscoveredModel(provider: .openAI, modelID: "x", kind: .text, isNew: true)
        let merged = ModelDiscovery.merge(previous: baseline + [other], fetched: second, provider: .groq, catalogIDs: ["catalog"], isFirstSearch: false)
        XCTAssertEqual(Set(merged.filter(\.isNew).map(\.id)), ["groq:c", "openAI:x"])
        XCTAssertEqual(merged.count, 5, "Other providers are kept; models no longer listed are dropped")
    }
}
