import XCTest
@testable import OpenNoTypeCore

final class ProviderTransportBoundsTests: XCTestCase {
    func testRejectsDeclaredOversizeBeforeWaitingForBody() async throws {
        let harness = BoundsHarness(.init(headers: ["Content-Length": "65", "Content-Type": "application/json"], chunks: [Data([65])], finishes: false))
        do { _ = try await harness.receive(limit: 64); XCTFail("Expected size rejection") }
        catch { XCTAssertEqual(error as? ProviderError, .responseTooLarge) }
        await harness.waitForStop()
        XCTAssertGreaterThan(harness.stops, 0)
    }

    func testRejectsUnannouncedContinuousBodyAtTheLimit() async throws {
        let harness = BoundsHarness(.init(chunks: Array(repeating: Data(repeating: 65, count: 16), count: 100),
                                          interval: 0.01, finishes: false))
        do { _ = try await harness.receive(limit: 64); XCTFail("Expected size rejection") }
        catch { XCTAssertEqual(error as? ProviderError, .responseTooLarge) }
        await harness.waitForStop()
        XCTAssertGreaterThan(harness.stops, 0)
    }

    func testAcceptsExactBoundaryAndPreservesHTTPStatus() async throws {
        let harness = BoundsHarness(.init(status: 429, chunks: [Data(repeating: 65, count: 64)]))
        let result = try await harness.receive(limit: 64)
        XCTAssertEqual(result.data.count, 64)
        XCTAssertEqual(result.http.statusCode, 429)
    }

    func testWholeDeadlineStopsBodyThatKeepsArriving() async throws {
        let harness = BoundsHarness(.init(chunks: Array(repeating: Data([65]), count: 100),
                                          interval: 0.01, finishes: false))
        let start = ProcessInfo.processInfo.systemUptime
        do { _ = try await harness.receive(limit: 1_000, timeout: 0.15); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? ProviderError, .timedOut) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        await harness.waitForStop()
        XCTAssertGreaterThan(harness.stops, 0)
    }

    func testCancellationStopsStream() async throws {
        let harness = BoundsHarness(.init(chunks: [], finishes: false))
        let task = Task { try await harness.receive(limit: 64) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await harness.waitForStop()
        XCTAssertGreaterThan(harness.stops, 0)
    }

    func testProviderTimeoutDoesNotRetryAndReportsFailedUsage() async throws {
        let harness = BoundsHarness(.init(chunks: [], finishes: false))
        let client = ProviderClient(session: harness.session, timeout: 0.15)
        let recorder = BoundsUsageRecorder()
        let request = ProcessingRequest(mode: .dictation, transcript: "synthetic text")
        do {
            _ = try await client.process(request, configuration: .init(provider: .groq,
                apiKey: "synthetic-test-key", transcriptionModel: "whisper-large-v3-turbo", textModel: "openai/gpt-oss-120b"),
                onUsage: { await recorder.append($0) })
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? ProviderError, .timedOut) }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.outcome, .failed)
        XCTAssertEqual(events.first?.attempt, 1)
        XCTAssertNil(events.first?.providerCostUSD)
    }
}

private actor BoundsUsageRecorder {
    var events: [ProviderUsage] = []
    func append(_ value: ProviderUsage) { events.append(value) }
}

private struct BoundsStub {
    var status = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var chunks: [Data]
    var interval: TimeInterval = 0
    var finishes = true
}

private final class BoundsHarness: @unchecked Sendable {
    let id = UUID().uuidString
    let session: URLSession
    var stops: Int { BoundsProtocol.statistics(id).0 }
    var delivered: Int { BoundsProtocol.statistics(id).1 }
    init(_ stub: BoundsStub) {
        BoundsProtocol.register(id, stub: stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundsProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Bounds-Test": id]
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel(); BoundsProtocol.remove(id) }
    func receive(limit: Int, timeout: TimeInterval = 1) async throws -> BoundedProviderResponse {
        try await BoundedProviderResponse.receive(URLRequest(url: URL(string: "https://example.invalid/synthetic")!),
            session: session, maximumBytes: limit, timeout: timeout)
    }
    func waitForStop() async {
        for _ in 0..<50 where stops == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
    }
}

private final class BoundsProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var stubs: [String: BoundsStub] = [:]
    private static var counts: [String: (Int, Int)] = [:]
    private let deliveryLock = NSRecursiveLock()
    private var stopped = false
    private var pending: DispatchWorkItem?
    static func register(_ id: String, stub: BoundsStub) {
        lock.lock(); defer { lock.unlock() }; stubs[id] = stub; counts[id] = (0, 0)
    }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; stubs[id] = nil; counts[id] = nil }
    static func statistics(_ id: String) -> (Int, Int) { lock.lock(); defer { lock.unlock() }; return counts[id] ?? (0, 0) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private var id: String { request.value(forHTTPHeaderField: "X-Bounds-Test") ?? "" }
    override func startLoading() {
        Self.lock.lock(); let stub = Self.stubs[id]; Self.lock.unlock()
        guard let stub else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        guard !stopped else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        schedule(stub, index: 0)
    }
    private func schedule(_ stub: BoundsStub, index: Int) {
        guard !stopped else { return }
        if index == stub.chunks.count {
            if stub.finishes { client?.urlProtocolDidFinishLoading(self) }
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deliveryLock.lock(); defer { self.deliveryLock.unlock() }
            guard !self.stopped else { return }
            self.client?.urlProtocol(self, didLoad: stub.chunks[index])
            Self.lock.lock(); var count = Self.counts[self.id] ?? (0, 0); count.1 += 1; Self.counts[self.id] = count; Self.lock.unlock()
            self.schedule(stub, index: index + 1)
        }
        pending = item
        DispatchQueue.global().asyncAfter(deadline: .now() + stub.interval, execute: item)
    }
    override func stopLoading() {
        deliveryLock.lock(); stopped = true; pending?.cancel(); pending = nil; deliveryLock.unlock()
        Self.lock.lock(); var count = Self.counts[id] ?? (0, 0); count.0 += 1; Self.counts[id] = count; Self.lock.unlock()
    }
}
