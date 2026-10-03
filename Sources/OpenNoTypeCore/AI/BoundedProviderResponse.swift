import Foundation

/// Bound memory while receiving, including responses with no Content-Length header.
struct BoundedProviderResponse: @unchecked Sendable {
    let data: Data
    let http: HTTPURLResponse

    static func receive(_ request: URLRequest, session: URLSession,
                        maximumBytes: Int, timeout: TimeInterval) async throws -> Self {
        guard maximumBytes > 0, timeout.isFinite, timeout > 0 else { throw ProviderError.timedOut }
        let receiver = ProviderResponseReceiver(maximumBytes: maximumBytes)
        return try await withThrowingTaskGroup(of: Self.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await receiver.receive(request, configuration: session.configuration)
                } onCancel: { receiver.cancel() }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(min(timeout, 120) * 1_000_000_000))
                throw ProviderError.timedOut
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else { throw ProviderError.invalidResponse }
            return response
        }
    }
}

/// A data delegate bounds chunks at delivery; unlike data(for:), it never accumulates an
/// unchecked full body. A private session copies the caller's configuration, including test
/// URLProtocols. Every exit invalidates it. State and continuation are completed exactly once.
private final class ProviderResponseReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<BoundedProviderResponse, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var completed = false
    private var expectedURL: URL?

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    func receive(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> BoundedProviderResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !completed else {
                lock.unlock(); continuation.resume(throwing: CancellationError()); return
            }
            self.continuation = continuation
            expectedURL = request.url
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            let task = session.dataTask(with: request)
            self.session = session; self.task = task
            lock.unlock()
            task.resume()
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == expectedURL else {
            finish(.failure(ProviderError.invalidResponse)); completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            finish(.failure(ProviderError.responseTooLarge)); completionHandler(.cancel); return
        }
        lock.lock()
        let cancelled = completed
        if !cancelled {
            self.response = http
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        }
        lock.unlock()
        completionHandler(cancelled ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        guard chunk.count <= maximumBytes - data.count else {
            lock.unlock(); finish(.failure(ProviderError.responseTooLarge)); return
        }
        data.append(chunk)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let result = response.map { BoundedProviderResponse(data: data, http: $0) }
        lock.unlock()
        if let result { finish(.success(result)) }
        else { finish(.failure(ProviderError.invalidResponse)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Credentials and private input never leave the selected provider endpoint.
        completionHandler(nil)
    }

    private func finish(_ result: Result<BoundedProviderResponse, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = self.continuation, task = self.task, session = self.session
        self.continuation = nil; self.task = nil; self.session = nil
        data = Data()
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
