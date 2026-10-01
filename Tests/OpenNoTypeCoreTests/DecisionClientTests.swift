import XCTest
@testable import OpenNoTypeCore

final class DecisionClientTests: XCTestCase {
    private let input = DecisionRequest(transcript: "오픈 라우터에 연결해 주세요.", cleanedText: "OpenRouter에 연결해 주세요.",
        termCandidates: [.init(id: "router", original: "오픈 라우터", candidate: "OpenRouter")])

    func testOneRequestContainsIndependentQuestionsAndOnlyApprovedTerms() async throws {
        let input = input
        let harness = DecisionHarness { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/alpha/decisions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 1.5)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
            XCTAssertFalse(request.httpShouldHandleCookies)
            let object = try request.decisionBody()
            XCTAssertEqual(Set(object.keys), Set(["model", "state", "questions", "provider"]))
            XCTAssertEqual(object["model"] as? String, DecisionClient.model)
            let state = try XCTUnwrap(object["state"] as? [String: Any])
            XCTAssertEqual(state["transcript"] as? String, input.transcript)
            XCTAssertEqual(state["cleaned_text"] as? String, input.cleanedText)
            XCTAssertEqual(state["approved_terms"] as? [[String: String]],
                           [["id": "term_0", "original": "오픈 라우터", "candidate": "OpenRouter"]])
            let questions = try XCTUnwrap(object["questions"] as? [String: [String: Any]])
            XCTAssertEqual(Set(questions.keys), Set(["meaning_changed", "content_added", "content_omitted", "term_0"]))
            XCTAssertTrue(questions.values.allSatisfy { ($0["instructions"] as? String)?.contains("quoted data") == true })
            XCTAssertEqual(questions["term_0"]?["type"] as? String, "choice")
            XCTAssertEqual(Set(try XCTUnwrap(questions["term_0"]?["criteria"] as? [String: String]).keys),
                           Set(["use_candidate", "keep_original", "uncertain"]))
            XCTAssertFalse(String(decoding: try JSONSerialization.data(withJSONObject: questions), as: UTF8.self).contains(input.transcript))
            return .json(Self.validResponse())
        }
        let result = try await harness.client.evaluate(input, apiKey: "synthetic-test-key")
        XCTAssertEqual(harness.count, 1)
        XCTAssertEqual(result.meaningChanged, 0.02)
        XCTAssertEqual(result.maximumRiskProbability, 0.04)
        XCTAssertEqual(result.terms.first?.id, "router")
        XCTAssertEqual(result.terms.first?.choice, .useCandidate)
        XCTAssertEqual(result.usage?.stage, .decisionReview)
        XCTAssertEqual(result.usage?.inputTokens, 600)
        XCTAssertEqual(result.usage?.providerCostUSD, 0.0000252)
    }

    func testHTTPFailureDoesNotRetryOrExposeRawProviderBody() async {
        let harness = DecisionHarness { _ in .init(status: 429, data: Data("synthetic-private-key-and-transcript".utf8)) }
        let recorder = DecisionUsageRecorder()
        do {
            _ = try await harness.client.evaluate(input, apiKey: "synthetic-test-key", onUsage: { await recorder.append($0) })
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? DecisionError, .httpStatus(429))
            XCTAssertFalse(error.localizedDescription.contains("synthetic-private"))
        }
        XCTAssertEqual(harness.count, 1)
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.outcome, .failed)
        XCTAssertNil(events.first?.providerCostUSD)
    }

    func testRedirectNeverSendsCredentialToAnotherHost() async {
        let harness = DecisionHarness { request in
            XCTAssertEqual(request.url?.host, "openrouter.ai")
            return .init(status: 307, headers: ["Location": "https://other.example/collect"], data: Data())
        }
        do { _ = try await harness.client.evaluate(input, apiKey: "synthetic-test-key"); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? DecisionError, .httpStatus(307)) }
        XCTAssertEqual(harness.count, 1)
    }

    func testNetworkTimeoutStopsTheSingleRequest() async {
        let harness = DecisionHarness { _ in .init(data: Data(), neverCompletes: true) }
        let start = Date()
        do { _ = try await harness.client.evaluate(input, apiKey: "synthetic-test-key"); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? DecisionError, .timedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(harness.count, 1)
        // URLSession delivers the loader's cancellation callback asynchronously.
        for _ in 0..<50 where harness.stopped == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertGreaterThanOrEqual(harness.stopped, 1)
    }

    func testCancellationStopsRequestAndReportsUnknownCost() async throws {
        let harness = DecisionHarness { _ in .init(data: Data(), neverCompletes: true) }
        let recorder = DecisionUsageRecorder()
        let input = input
        let operation = Task {
            try await harness.client.evaluate(input, apiKey: "synthetic-test-key", onUsage: { await recorder.append($0) })
        }
        for _ in 0..<50 where harness.count == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.outcome, .cancelled)
        XCTAssertNil(events.first?.providerCostUSD)
        XCTAssertEqual(harness.count, 1)
    }

    func testResponseBoundsRejectContentLengthAndUnannouncedBody() async {
        for headers in [["Content-Length": "128001"], [:]] {
            let harness = DecisionHarness { _ in
                .init(headers: headers, data: Data(repeating: 65, count: DecisionClient.maximumResponseBytes + 1))
            }
            do { _ = try await harness.client.evaluate(input, apiKey: "synthetic-test-key"); XCTFail("Expected size rejection") }
            catch { XCTAssertEqual(error as? DecisionError, .responseTooLarge) }
            XCTAssertEqual(harness.count, 1)
        }
    }

    func testValidationRejectsBeforeAnyRequest() async {
        let harness = DecisionHarness { _ in XCTFail("Must not send"); return .json(Self.validResponse()) }
        let invalidInputs = [
            DecisionRequest(transcript: " ", cleanedText: "text"),
            DecisionRequest(transcript: String(repeating: "가", count: 8_001), cleanedText: "text"),
            DecisionRequest(transcript: "text", cleanedText: "text", termCandidates: Array(repeating: input.termCandidates[0], count: 17)),
            DecisionRequest(transcript: "text", cleanedText: "text", termCandidates: Array(repeating: input.termCandidates[0], count: 2)),
            DecisionRequest(transcript: "text", cleanedText: "text", termCandidates: [.init(id: "one", original: "line\nbreak", candidate: "term")])
        ]
        for value in invalidInputs {
            do { _ = try await harness.client.evaluate(value, apiKey: "synthetic-test-key"); XCTFail("Expected rejection") }
            catch { XCTAssertTrue(error is DecisionError) }
        }
        for key in ["", "bad\r\nheader", "bad\tkey", "bad key", "키값"] {
            do { _ = try await harness.client.evaluate(input, apiKey: key); XCTFail("Expected invalid key") }
            catch { XCTAssertEqual(error as? DecisionError, .missingAPIKey) }
        }
        XCTAssertEqual(harness.count, 0)
    }

    func testMalformedSuccessfulOutputStillReportsUsage() async {
        var object = Self.validResponse()
        object["answers"] = [:]
        let harness = DecisionHarness { _ in .json(object) }
        let recorder = DecisionUsageRecorder()
        do {
            _ = try await harness.client.evaluate(input, apiKey: "synthetic-test-key", onUsage: { await recorder.append($0) })
            XCTFail("Expected malformed response")
        } catch { XCTAssertEqual(error as? DecisionError, .invalidResponse) }
        let events = await recorder.events
        XCTAssertEqual(events.first?.providerCostUSD, 0.0000252)
        XCTAssertEqual(events.first?.outcome, .responseReceived)
    }

    func testMissingUsageCostRemainsUnknown() async throws {
        var object = Self.validResponse()
        object["usage"] = ["input_tokens": 400]
        let harness = DecisionHarness { _ in .json(object) }
        let result = try await harness.client.evaluate(input, apiKey: "synthetic-test-key")
        XCTAssertNil(result.usage?.providerCostUSD)
        XCTAssertNil(result.usage?.outputTokens)
        XCTAssertEqual(result.usage?.inputTokens, 400)
    }

    func testUnexpectedReportedModelCannotEnterUsageHistory() async {
        var object = Self.validResponse()
        object["model"] = "synthetic-private-key-echo"
        let harness = DecisionHarness { _ in .json(object) }
        let recorder = DecisionUsageRecorder()
        do {
            _ = try await harness.client.evaluate(input, apiKey: "synthetic-test-key", onUsage: { await recorder.append($0) })
            XCTFail("Expected malformed response")
        } catch { XCTAssertEqual(error as? DecisionError, .invalidResponse) }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.reportedModel)
        XCTAssertEqual(events.first?.providerCostUSD, 0.0000252)
    }

    func testParserRejectsWrongMissingAndExtraAnswerKeys() {
        for key in ["meaning_changed", "content_added", "content_omitted", "term_0"] {
            var object = Self.validResponse()
            var answers = object["answers"] as! [String: Any]
            answers[key] = nil
            object["answers"] = answers
            assertInvalid(object)
        }
        var object = Self.validResponse()
        var answers = object["answers"] as! [String: Any]
        answers["invented"] = ["type": "noul", "noul": 0.5]
        object["answers"] = answers
        assertInvalid(object)
    }

    func testParserRejectsInvalidNoulTypesAndProbabilities() {
        for value: Any in [true, "0.9", -0.01, 1.01, Double.nan, Double.infinity, NSNull()] {
            var object = Self.validResponse()
            var answers = object["answers"] as! [String: Any]
            answers["meaning_changed"] = ["type": "noul", "noul": value]
            object["answers"] = answers
            assertInvalid(object)
        }
    }

    func testParserRejectsChoiceContractViolations() {
        let mutations: [[String: Any]] = [
            ["choice": "invented"], ["choice": "keep_original"], ["confidence": true], ["confidence": -1],
            ["confidence": Double.nan], ["type": "score"], ["unexpected": "text"],
            ["probabilities": ["use_candidate": 1]],
            ["probabilities": ["use_candidate": 0.5, "keep_original": 0.5, "uncertain": 0.5]],
            ["probabilities": ["use_candidate": true, "keep_original": 0, "uncertain": 0]]
        ]
        for mutation in mutations {
            var object = Self.validResponse()
            var answers = object["answers"] as! [String: Any]
            var answer = answers["term_0"] as! [String: Any]
            answer.merge(mutation) { _, new in new }
            answers["term_0"] = answer
            object["answers"] = answers
            assertInvalid(object)
        }
    }

    func testModelMustBePinnedFamilyAndProviderErrorsCannotBeAccepted() {
        for model in ["", "unrelated/model", "typesafe/jev-1.139", "typesafe/jev-1.13-", "typesafe/jev-1.13-\nprivate"] {
            var object = Self.validResponse(); object["model"] = model; assertInvalid(object)
        }
        var object = Self.validResponse(); object["error"] = ["message": "private body"]
        assertInvalid(object)
    }

    func testNoTermsUsesOnlySemanticJudgmentsAndDoesNotRequireCandidateAnswer() async throws {
        var object = Self.validResponse()
        var answers = object["answers"] as! [String: Any]; answers["term_0"] = nil; object["answers"] = answers
        let harness = DecisionHarness { _ in .json(object) }
        let result = try await harness.client.evaluate(.init(transcript: "오늘은 쉬어요.", cleanedText: "오늘은 쉬어요."), apiKey: "synthetic-test-key")
        XCTAssertTrue(result.terms.isEmpty)
    }

    func testEmptyCleanedTextCanBeReviewedAsAnOmission() async throws {
        var object = Self.validResponse()
        var answers = object["answers"] as! [String: Any]
        answers["term_0"] = nil
        answers["content_omitted"] = ["type": "noul", "noul": 1]
        object["answers"] = answers
        let harness = DecisionHarness { request in
            let state = try XCTUnwrap(try request.decisionBody()["state"] as? [String: Any])
            XCTAssertEqual(state["cleaned_text"] as? String, "")
            return .json(object)
        }
        let result = try await harness.client.evaluate(.init(transcript: "내일 회의를 취소해 주세요.", cleanedText: ""), apiKey: "synthetic-test-key")
        XCTAssertEqual(result.contentOmitted, 1)
        XCTAssertEqual(harness.count, 1)
    }

    private func assertInvalid(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try DecisionClient.parse(object, candidates: input.termCandidates,
            usage: .init(provider: .openRouter, model: DecisionClient.model, stage: .decisionReview)), file: file, line: line) {
                XCTAssertEqual($0 as? DecisionError, .invalidResponse, file: file, line: line)
            }
    }

    private static func validResponse() -> [String: Any] {
        ["model": "typesafe/jev-1.13-20260917", "usage": ["input_tokens": 600, "output_tokens": 60, "cost": 0.0000252],
         "answers": ["meaning_changed": ["type": "noul", "noul": 0.02],
                     "content_added": ["type": "noul", "noul": 0.03],
                     "content_omitted": ["type": "noul", "noul": 0.04],
                     "term_0": ["type": "choice", "choice": "use_candidate", "confidence": 0.9,
                                "probabilities": ["use_candidate": 0.95, "keep_original": 0.03, "uncertain": 0.02]]]]
    }
}

private actor DecisionUsageRecorder {
    var events: [ProviderUsage] = []
    func append(_ event: ProviderUsage) { events.append(event) }
}

private struct DecisionStubResponse {
    var status = 200
    var headers: [String: String] = [:]
    var data: Data
    var neverCompletes = false
    static func json(_ object: [String: Any]) -> Self {
        .init(headers: ["Content-Type": "application/json"], data: try! JSONSerialization.data(withJSONObject: object))
    }
}

private final class DecisionHarness {
    let id = UUID().uuidString
    let session: URLSession
    let client: DecisionClient
    var count: Int { DecisionStubProtocol.count(id) }
    var stopped: Int { DecisionStubProtocol.stopped(id) }
    init(handler: @escaping (URLRequest) throws -> DecisionStubResponse) {
        DecisionStubProtocol.register(id, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DecisionStubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Decision-Test": id]
        session = URLSession(configuration: configuration)
        client = DecisionClient(session: session)
    }
    deinit { session.invalidateAndCancel(); DecisionStubProtocol.remove(id) }
}

private final class DecisionStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) throws -> DecisionStubResponse] = [:]
    private static var counts: [String: Int] = [:]
    private static var stops: [String: Int] = [:]
    static func register(_ id: String, handler: @escaping (URLRequest) throws -> DecisionStubResponse) {
        lock.lock(); defer { lock.unlock() }; handlers[id] = handler; counts[id] = 0; stops[id] = 0
    }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; handlers[id] = nil; counts[id] = nil; stops[id] = nil }
    static func count(_ id: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[id] ?? 0 }
    static func stopped(_ id: String) -> Int { lock.lock(); defer { lock.unlock() }; return stops[id] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Decision-Test") ?? ""
        Self.lock.lock(); let handler = Self.handlers[id]; Self.counts[id, default: 0] += 1; Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let stub = try handler(request)
            if stub.neverCompletes { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            if (300...399).contains(stub.status), let target = stub.headers["Location"].flatMap(URL.init(string:)) {
                var redirect = request; redirect.url = target
                client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {
        let id = request.value(forHTTPHeaderField: "X-Decision-Test") ?? ""
        Self.lock.lock(); Self.stops[id, default: 0] += 1; Self.lock.unlock()
    }
}

private extension URLRequest {
    func decisionBody() throws -> [String: Any] {
        var data = httpBody ?? Data()
        if httpBody == nil, let stream = httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw DecisionError.invalidInput }
                if count == 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
