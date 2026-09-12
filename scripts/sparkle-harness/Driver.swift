// Synthetic Sparkle driver only. Never link OpenNoType or accept production bundles.
import AppKit
import Foundation
import Sparkle

@MainActor
final class HarnessDriver: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUUserDriver {
    private var updater: SPUUpdater?
    private var root: URL!
    private var feed: URL!
    private var completed = false
    private var downloadedBytes: UInt64 = 0

    private func event(_ name: String, _ fields: [String: Any] = [:]) {
        guard let root else { return }
        var value = fields
        value["event"] = name
        value["pid"] = ProcessInfo.processInfo.processIdentifier
        value["time"] = Date().timeIntervalSince1970
        let path = root.appendingPathComponent("events.jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        if !FileManager.default.fileExists(atPath: path.path) { FileManager.default.createFile(atPath: path.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data([10]))
        }
    }

    private func finish(_ outcome: String, error: Error? = nil) {
        guard !completed, let root else { return }
        completed = true
        var result: [String: Any] = ["outcome": outcome, "downloaded_bytes": downloadedBytes,
                                     "production_artifact_tested": false]
        if let error {
            let nsError = error as NSError
            result["error_domain"] = nsError.domain
            result["error_code"] = nsError.code
            result["error_description"] = nsError.localizedDescription
            var chain: [[String: Any]] = []
            var current: NSError? = nsError
            while let item = current, chain.count < 8 {
                chain.append(["domain": item.domain, "code": item.code, "description": item.localizedDescription])
                current = item.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            result["error_chain"] = chain
        }
        event(outcome)
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("driver-result.json"), options: .atomic)
        }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let rootPath = info["HarnessRoot"] as? String,
              let driverID = Bundle.main.bundleIdentifier,
              driverID.hasPrefix("app.opennotype.sparkle-harness."), driverID.hasSuffix(".driver"),
              let hostID = info["HarnessHostID"] as? String,
              hostID == driverID.replacingOccurrences(of: ".driver", with: ".host") else { exit(2) }
        let root = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath()
        guard root.lastPathComponent.hasPrefix("opennotype-sparkle-harness-"),
              Bundle.main.bundleURL.resolvingSymlinksInPath() == root.appendingPathComponent("Driver.app") else { exit(2) }
        self.root = root
        let target = root.appendingPathComponent("Target.app")
        guard target.resolvingSymlinksInPath() == target,
              let host = Bundle(url: target), host.bundleIdentifier == hostID,
              let feedText = host.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feed = URL(string: feedText), feed.scheme == "http", feed.host == "127.0.0.1",
              feed.user == nil, feed.password == nil, feed.path == "/appcast.xml", feed.query == nil,
              feed.fragment == nil, feed.port != nil else { finish("unsafe-configuration"); return }
        self.feed = feed
        let build = host.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        event("driver-launched", ["target_build": build ?? "unknown", "driver_bundle_id": driverID, "host_bundle_id": hostID])
        if build == "2" { finish("relaunched-with-updated-target"); return }
        guard build == "1" else { finish("unexpected-target-build"); return }
        updater = SPUUpdater(hostBundle: host, applicationBundle: Bundle.main, userDriver: self, delegate: self)
        do {
            try updater?.start()
            updater?.checkForUpdates()
        } catch { finish("startup-failed", error: error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 150) { [weak self] in self?.finish("driver-timeout") }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        event("driver-termination-requested")
        return .terminateNow
    }

    func feedURLString(for updater: SPUUpdater) -> String? { feed.absoluteString }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard item.versionString == "2", item.fileURL == feed.deletingLastPathComponent().appendingPathComponent("Target-2.zip"),
              !item.isInformationOnlyUpdate else { throw NSError(domain: "harness.rejected-item", code: 1) }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { event("sparkle-will-install", ["version": item.versionString]) }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error { finish("update-rejected", error: error) }
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { event("checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        event("update-found", ["version": appcastItem.versionString]); reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { finish("unexpected-release-notes", error: error) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish("update-not-found", error: error)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish("update-rejected", error: error)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { event("download-started") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { event("download-length", ["bytes": expectedContentLength]) }
    func showDownloadDidReceiveData(ofLength length: UInt64) { downloadedBytes += length }
    func showDownloadDidStartExtractingUpdate() { event("extracting", ["downloaded_bytes": downloadedBytes]) }
    func showExtractionReceivedProgress(_ progress: Double) { }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { event("ready-to-install"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        event("installing", ["driver_already_terminated": applicationTerminated])
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        event("installation-finished", ["relaunched": relaunched]); acknowledgement()
    }
    func dismissUpdateInstallation() { event("dismissed") }
}

@main
enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let driver = HarnessDriver()
        app.delegate = driver
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(driver) { app.run() }
    }
}
