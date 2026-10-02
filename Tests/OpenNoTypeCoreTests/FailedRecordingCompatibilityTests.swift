import Foundation
import XCTest
@testable import OpenNoTypeCore

final class FailedRecordingCompatibilityTests: XCTestCase {
    func testLegacyFailureWithoutTextProviderKeepsStoredMetadata() throws {
        let data = Data(#"""
        {"id":"7D3F0C7A-3C3A-4E7B-9D5B-0F5B8B6A1C11","createdAt":123,"expiresAt":86523,
         "mode":"translation","provider":"groq","targetLanguage":"Korean",
         "transcriptionModel":"recorded-stt","textModel":"recorded-text",
         "usedLocalTranscription":false,"usedSpeakerFilter":true}
        """#.utf8)

        let item = try JSONDecoder().decode(FailedRecording.self, from: data)

        XCTAssertEqual(item.id.uuidString, "7D3F0C7A-3C3A-4E7B-9D5B-0F5B8B6A1C11")
        XCTAssertEqual(item.createdAt, Date(timeIntervalSinceReferenceDate: 123))
        XCTAssertEqual(item.expiresAt, Date(timeIntervalSinceReferenceDate: 86523))
        XCTAssertEqual(item.mode, .translation)
        XCTAssertEqual(item.provider, .groq)
        XCTAssertNil(item.textProvider)
        XCTAssertEqual(item.textProvider ?? item.provider, .groq)
        XCTAssertEqual(item.targetLanguage, "Korean")
        XCTAssertEqual(item.transcriptionModel, "recorded-stt")
        XCTAssertEqual(item.textModel, "recorded-text")
        XCTAssertEqual(item.usedLocalTranscription, false)
        XCTAssertEqual(item.usedSpeakerFilter, true)
    }

    func testSplitFailureRoundTripKeepsProvidersAndAudioIdentityIndependent() throws {
        let item = FailedRecording(createdAt: Date(timeIntervalSinceReferenceDate: 123),
                                   mode: .dictation, provider: .groq, textProvider: .openRouter,
                                   targetLanguage: "Korean", transcriptionModel: "recorded-stt",
                                   textModel: "recorded-text", usedLocalTranscription: false,
                                   usedSpeakerFilter: true,
                                   writingProfile: .init(kind: .development, tone: .polite))
        let data = try JSONEncoder().encode(item)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let restored = try JSONDecoder().decode(FailedRecording.self, from: data)

        XCTAssertEqual(object["provider"] as? String, "groq")
        XCTAssertEqual(object["textProvider"] as? String, "openRouter")
        XCTAssertEqual(restored.provider, .groq)
        XCTAssertEqual(restored.textProvider, .openRouter)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.createdAt, item.createdAt)
        XCTAssertEqual(restored.expiresAt, item.expiresAt)
        XCTAssertEqual(restored.transcriptionModel, item.transcriptionModel)
        XCTAssertEqual(restored.textModel, item.textModel)
        XCTAssertEqual(restored.usedLocalTranscription, item.usedLocalTranscription)
        XCTAssertEqual(restored.usedSpeakerFilter, item.usedSpeakerFilter)
        XCTAssertEqual(restored.writingProfile, item.writingProfile)
    }

    func testUnsetTextProviderPreservesLegacyWireFormatAndExplicitNullDecodes() throws {
        let item = FailedRecording(mode: .dictation, provider: .anthropic, targetLanguage: "Korean")
        let data = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["provider"] as? String, "anthropic")
        XCTAssertNil(object["textProvider"])
        object["textProvider"] = NSNull()
        let restored = try JSONDecoder().decode(FailedRecording.self,
                                               from: JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(restored.textProvider)
        XCTAssertEqual(restored.textProvider ?? restored.provider, .anthropic)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.expiresAt, item.expiresAt)
    }

    func testUnrecognizedOptionalTextProviderKeepsLegacyRouteAndAllRecordingMetadata() throws {
        var item = FailedRecording(id: UUID(uuidString: "7D3F0C7A-3C3A-4E7B-9D5B-0F5B8B6A1C11")!,
            createdAt: Date(timeIntervalSinceReferenceDate: 123), mode: .translation,
            provider: .groq, textProvider: .openRouter, targetLanguage: "Korean",
            transcriptionModel: "recorded-stt", textModel: "recorded-text",
            usedLocalTranscription: false, usedSpeakerFilter: true,
            writingProfile: .init(kind: .development, tone: .polite))
        item.expiresAt = Date(timeIntervalSinceReferenceDate: 4567)
        let data = try JSONEncoder().encode(item)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for unreadable in ["future-provider" as Any, 42] {
            var object = original
            object["textProvider"] = unreadable
            let restored = try JSONDecoder().decode(FailedRecording.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(restored.textProvider)
            XCTAssertEqual(restored.textProvider ?? restored.provider, .groq)
            XCTAssertEqual(restored.id, item.id)
            XCTAssertEqual(restored.createdAt, item.createdAt)
            XCTAssertEqual(restored.expiresAt, item.expiresAt)
            XCTAssertEqual(restored.mode, item.mode)
            XCTAssertEqual(restored.provider, item.provider)
            XCTAssertEqual(restored.targetLanguage, item.targetLanguage)
            XCTAssertEqual(restored.transcriptionModel, item.transcriptionModel)
            XCTAssertEqual(restored.textModel, item.textModel)
            XCTAssertEqual(restored.usedLocalTranscription, item.usedLocalTranscription)
            XCTAssertEqual(restored.usedSpeakerFilter, item.usedSpeakerFilter)
            XCTAssertEqual(restored.writingProfile, item.writingProfile)
        }
    }
}
