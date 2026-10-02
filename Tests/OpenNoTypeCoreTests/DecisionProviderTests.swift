import XCTest
@testable import OpenNoTypeCore

final class DecisionProviderTests: XCTestCase {
    func testDirectUsageIsCloudAndUsesOnlyEstimatedInputPrice() {
        let usage = ProviderUsage(decisionProvider: .typeSafe, model: "jev-1.13.0", reportedModel: "jev-1.13.0", stage: .decisionReview,
                                  httpStatus: 200, inputTokens: 1_000_000, outputTokens: 500_000,
                                  providerCostUSD: 99)
        XCTAssertEqual(usage.providerID, "typesafe")
        XCTAssertEqual(usage.providerDisplayName, "TypeSafe")
        XCTAssertFalse(usage.isLocal)
        let cost = UsagePricing.cost(for: usage)
        XCTAssertEqual(cost.kind, .estimated)
        XCTAssertEqual(cost.usd, 0.042)
        XCTAssertEqual(cost.rateSnapshot?.outputPerMillion, 0)
        XCTAssertEqual(cost.sourceURL, "https://docs.typesafe.ai/models")
        XCTAssertEqual(cost.checkedAt, "2026-10-01")
    }

    func testDirectMissingTokensFailureAndUnknownModelNeverBecomeLocalOrZero() {
        let base = ProviderUsage(decisionProvider: .typeSafe, model: "jev-1.13.0", reportedModel: "jev-1.13.0", stage: .decisionReview,
                                 httpStatus: 200, inputTokens: 10, outputTokens: 20)
        var cases: [ProviderUsage] = []
        var item = base; item.inputTokens = nil; cases.append(item)
        item = base; item.outputTokens = nil; cases.append(item)
        item = base; item.inputTokens = -1; cases.append(item)
        item = base; item.outputTokens = -1; cases.append(item)
        item = base; item.outcome = .failed; cases.append(item)
        item = base; item.outcome = .cancelled; cases.append(item)
        item = base; item.httpStatus = 429; cases.append(item)
        item = base; item.reportedModel = "future-model"; cases.append(item)
        item = base; item.reportedModel = nil; cases.append(item)
        item = base; item.model = "unknown-model"; cases.append(item)
        item = base; item.stage = .textProcessing; cases.append(item)
        item = base; item.provider = .openRouter; cases.append(item)
        for usage in cases {
            XCTAssertFalse(usage.isLocal)
            XCTAssertEqual(UsagePricing.cost(for: usage).kind, .unavailable)
            XCTAssertNil(UsagePricing.cost(for: usage).usd)
        }
    }

    func testLegacyUsageDecodesWithoutDecisionProviderAndRetainsProviderClassification() throws {
        for provider: AIProvider? in [nil, .openRouter, .groq] {
            let original = ProviderUsage(provider: provider, model: "legacy-model", stage: .transcription)
            let encoded = try JSONEncoder().encode(original)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object.removeValue(forKey: "decisionProvider")
            let data = try JSONSerialization.data(withJSONObject: object)
            let decoded = try JSONDecoder().decode(ProviderUsage.self, from: data)
            XCTAssertNil(decoded.decisionProvider)
            XCTAssertEqual(decoded.providerID, provider?.rawValue ?? "local")
            XCTAssertEqual(decoded.isLocal, provider == nil)
            XCTAssertEqual(decoded, original)
        }
    }

    func testDirectUsageRoundTripPreservesCloudIdentityAndCostSnapshot() throws {
        let event = ProviderUsage(decisionProvider: .typeSafe, model: "jev-1.13.0", reportedModel: "jev-1.13.0", stage: .decisionReview,
                                  inputTokens: 600, outputTokens: 60)
        let record = UsageRecord(jobID: UUID(), mode: .dictation, event: event)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(UsageRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.event.providerID, "typesafe")
        XCTAssertEqual(decoded.cost.kind, .estimated)
        XCTAssertFalse(decoded.event.isLocal)
    }

    func testRouterDecisionIdentityCanUseExistingCostSemanticsWithoutAIProvider() {
        let usage = ProviderUsage(decisionProvider: .openRouter, model: DecisionProvider.openRouter.model,
                                  stage: .decisionReview, providerCostUSD: 0.00001)
        XCTAssertEqual(usage.providerID, "openRouter")
        XCTAssertEqual(usage.providerDisplayName, "OpenRouter")
        XCTAssertFalse(usage.isLocal)
        XCTAssertEqual(UsagePricing.cost(for: usage).kind, .providerReported)
    }

    func testDecisionKeysShareRouterAccountAndKeepTypeSafeIndependent() throws {
        let backend = DecisionMemorySecretBackend()
        try KeychainSecrets.save("synthetic-router", for: .openRouter, backend: backend)
        try KeychainSecrets.save("synthetic-groq", for: .groq, backend: backend)
        let existing = try KeychainSecrets.readDecisionKey(for: .openRouter, backend: backend)
        XCTAssertEqual(existing, "synthetic-router")
        try KeychainSecrets.saveDecisionKey("synthetic-typesafe", for: .typeSafe, backend: backend)
        XCTAssertEqual(Set(backend.accounts), Set(["openRouter", "groq", "typesafe"]))
        let direct = try KeychainSecrets.readDecisionKey(for: .typeSafe, backend: backend)
        XCTAssertEqual(direct, "synthetic-typesafe")
        try KeychainSecrets.saveDecisionKey("synthetic-router-replaced", for: .openRouter, backend: backend)
        let router = try KeychainSecrets.read(for: .openRouter, backend: backend)
        XCTAssertEqual(router, "synthetic-router-replaced")
        try KeychainSecrets.deleteDecisionKey(for: .typeSafe, backend: backend)
        XCTAssertEqual(Set(backend.accounts), Set(["openRouter", "groq"]))
        try KeychainSecrets.deleteDecisionKey(for: .openRouter, backend: backend)
        XCTAssertEqual(backend.accounts, ["groq"])
    }

    func testDecisionKeysRejectInvalidSecretWithoutOverwritingExistingValue() throws {
        let backend = DecisionMemorySecretBackend()
        try KeychainSecrets.saveDecisionKey("synthetic-typesafe", for: .typeSafe, backend: backend)
        XCTAssertThrowsError(try KeychainSecrets.saveDecisionKey(" \n ", for: .typeSafe, backend: backend)) {
            XCTAssertEqual($0 as? SecretStorageError, .invalidSecret)
        }
        let value = try KeychainSecrets.readDecisionKey(for: .typeSafe, backend: backend)
        XCTAssertEqual(value, "synthetic-typesafe")
        backend.values["typesafe"] = Data([0xff])
        XCTAssertThrowsError(try KeychainSecrets.readDecisionKey(for: .typeSafe, backend: backend)) {
            XCTAssertEqual($0 as? SecretStorageError, .invalidSecret)
        }
    }

    func testDecisionKeyBackendFailureRemainsAnError() {
        let backend = DecisionMemorySecretBackend()
        backend.failure = .keychain(-25293)
        XCTAssertThrowsError(try KeychainSecrets.readDecisionKey(for: .typeSafe, backend: backend))
        XCTAssertThrowsError(try KeychainSecrets.saveDecisionKey("synthetic-typesafe", for: .typeSafe, backend: backend))
        XCTAssertThrowsError(try KeychainSecrets.deleteDecisionKey(for: .typeSafe, backend: backend))
        XCTAssertTrue(backend.values.isEmpty)
    }
}

/// In-memory synthetic credentials only; these tests never access the system Keychain.
private final class DecisionMemorySecretBackend: SecretBackend, @unchecked Sendable {
    var values: [String: Data] = [:]
    var failure: SecretStorageError?
    var accounts: [String] { values.keys.sorted() }
    func read(service: String, account: String) throws -> Data? {
        XCTAssertEqual(service, "app.opennotype.provider-secrets")
        if let failure { throw failure }
        return values[account]
    }
    func save(_ data: Data, service: String, account: String) throws {
        XCTAssertEqual(service, "app.opennotype.provider-secrets")
        if let failure { throw failure }
        values[account] = data
    }
    func delete(service: String, account: String) throws {
        XCTAssertEqual(service, "app.opennotype.provider-secrets")
        if let failure { throw failure }
        values[account] = nil
    }
}
