import Foundation
import XCTest
@testable import OpenNoType
@testable import OpenNoTypeCore

@MainActor
final class JevModelComparisonTests: XCTestCase {
    private let models = ["inclusionai/ling-3.0-flash", "openai/gpt-oss-20b"]
    private var configuration: ProviderConfiguration {
        .init(provider: .openRouter, apiKey: "synthetic-key", transcriptionModel: "unused", textModel: "unchanged")
    }
    private var decisionConfiguration: DecisionConfiguration { .init(provider: .typeSafe, apiKey: "synthetic-key") }
    private func setup(output: String = "PRIVATE_APPROVED_SENTINEL", cost: Double? = 0.0001, status: Int = 200) -> (JevModelComparison, ProviderClient) {
        ComparisonURLProtocol.configure(output: output, cost: cost, status: status)
        let session = URLSessionConfiguration.ephemeral; session.protocolClasses = [ComparisonURLProtocol.self]
        let client = ProviderClient(session: URLSession(configuration: session))
        let model = JevModelComparison()
        model.cases = [.init(transcript: "인식 오류가 있는 원문", approvedText: "PRIVATE_APPROVED_SENTINEL")]
        model.selectedModels = models
        return (model, client)
    }

    func testSameSourceGoesToEveryModelAndApprovedAnswerOnlyGoesToReviewer() async throws {
        let (model, client) = setup(), reviewer = ComparisonReviewer()
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(ComparisonURLProtocol.requests.count, 2)
        for body in ComparisonURLProtocol.requests {
            XCTAssertFalse(body.contains("PRIVATE_APPROVED_SENTINEL"))
            XCTAssertTrue(body.contains("인식 오류가 있는 원문"))
            XCTAssertFalse(body.contains("previous_output"))
        }
        let reviews = await reviewer.requests
        XCTAssertEqual(reviews.count, 2)
        XCTAssertTrue(reviews.allSatisfy { $0.transcript == "PRIVATE_APPROVED_SENTINEL" })
        XCTAssertEqual(model.rows.map(\.passedCount), [1, 1])
        XCTAssertTrue(model.rows.allSatisfy { $0.totalCostUSD.map { $0 > 0 } == true })
        XCTAssertNotNil(model.recommendedModel)
        XCTAssertEqual(configuration.textModel, "unchanged")
    }

    func testUnknownGenerationCostStopsBeforeReviewAndRemainingModels() async {
        let (model, client) = setup(cost: nil), reviewer = ComparisonReviewer()
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        let requests = await reviewer.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(ComparisonURLProtocol.requests.count, 1)
        XCTAssertNil(model.recommendedModel)
        XCTAssertNil(model.rows.first?.totalCostUSD)
        XCTAssertFalse(model.isRunning)
    }

    func testMissingReviewUsageStopsInsteadOfAssumingFreeReview() async {
        let (model, client) = setup(), reviewer = ComparisonReviewer(providesUsage: false)
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        let requests = await reviewer.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(ComparisonURLProtocol.requests.count, 1)
        XCTAssertNil(model.recommendedModel)
        XCTAssertEqual(model.rows.first?.completedCount, 0)
        XCTAssertNil(model.rows.first?.totalCostUSD)
    }

    func testHTTPFailureDoesNotRetryOrSendOtherModels() async {
        let (model, client) = setup(status: 503), reviewer = ComparisonReviewer()
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        XCTAssertEqual(ComparisonURLProtocol.requests.count, 1)
        XCTAssertNil(model.recommendedModel)
        XCTAssertFalse(model.isRunning)
    }

    func testBudgetRefusalSendsNoRequestsAndShowsEstimate() async {
        let (model, client) = setup(), reviewer = ComparisonReviewer()
        model.budgetUSD = 0.000_001
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        XCTAssertTrue(ComparisonURLProtocol.requests.isEmpty)
        XCTAssertNotNil(model.estimatedReservationUSD)
        XCTAssertNotNil(model.status)
    }

    func testReportedChargeLeavesNoBudgetForReviewAndStops() async {
        let (model, client) = setup(cost: 0.05), reviewer = ComparisonReviewer()
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        let reviews = await reviewer.requests
        XCTAssertTrue(reviews.isEmpty)
        XCTAssertEqual(ComparisonURLProtocol.requests.count, 1)
        XCTAssertNil(model.recommendedModel)
        XCTAssertEqual(model.rows.first?.totalCostUSD, 0.05)
    }

    func testLiteralMismatchCannotBecomeRecommendationDespiteLowRisk() async {
        let (model, client) = setup(output: "WRONG_SENTINEL"), reviewer = ComparisonReviewer()
        await model.run(configuration: configuration, decisionConfiguration: decisionConfiguration,
                        dictionary: [], client: client, reviewer: reviewer)
        XCTAssertEqual(model.rows.map(\.completedCount), [1, 1])
        XCTAssertEqual(model.rows.map(\.passedCount), [0, 0])
        XCTAssertNil(model.recommendedModel)
    }

    func testSensitiveDataClearCancelsAndDiscardsLateReview() async throws {
        let (model, client) = setup(), gate = ComparisonGate(), reviewer = ComparisonReviewer()
        await reviewer.setGate(gate)
        let config = configuration, decision = decisionConfiguration
        let task = Task { await model.run(configuration: config, decisionConfiguration: decision,
                                          dictionary: [], client: client, reviewer: reviewer) }
        for _ in 0..<300 {
            if await gate.entered { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let entered = await gate.entered; XCTAssertTrue(entered)
        model.clearSensitiveData()
        await gate.release(); await task.value
        XCTAssertTrue(model.cases.isEmpty)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.recommendedModel)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(ComparisonURLProtocol.requests.count, 1)
    }
}

private actor ComparisonGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

private actor ComparisonReviewer: DecisionEvaluating {
    private(set) var requests: [DecisionRequest] = []
    private let providesUsage: Bool
    private var gate: ComparisonGate?
    init(providesUsage: Bool = true) { self.providesUsage = providesUsage }
    func setGate(_ value: ComparisonGate) { gate = value }
    func evaluate(_ input: DecisionRequest, configuration: DecisionConfiguration,
                  onUsage: (@Sendable (ProviderUsage) async -> Void)?) async throws -> DecisionResult {
        requests.append(input)
        await gate?.wait()
        let usage: ProviderUsage? = providesUsage ? .init(decisionProvider: .typeSafe, model: DecisionProvider.typeSafe.model,
            reportedModel: DecisionProvider.typeSafe.model, stage: .decisionReview, inputTokens: 100, outputTokens: 0) : nil
        if let usage { await onUsage?(usage) }
        return .init(meaningChanged: 0.01, contentAdded: 0.01, contentOmitted: 0.01, usage: usage)
    }
}

private final class ComparisonURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var bodies: [String] = []
    private static var output = ""
    private static var cost: Double? = 0.0001
    private static var status = 200
    static var requests: [String] { lock.lock(); defer { lock.unlock() }; return bodies }
    static func configure(output: String, cost: Double?, status: Int) {
        lock.lock(); defer { lock.unlock() }; bodies = []; self.output = output; self.cost = cost; self.status = status
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock(); Self.bodies.append(String(data: data, encoding: .utf8) ?? "")
        let output = Self.output, cost = Self.cost, status = Self.status; Self.lock.unlock()
        let text = String(data: try! JSONSerialization.data(withJSONObject: ["text": output]), encoding: .utf8)!
        var usage: [String: Any] = ["prompt_tokens": 100, "completion_tokens": 20]
        if let cost { usage["cost"] = cost }
        let object: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": text]]], "usage": usage]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "0"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
