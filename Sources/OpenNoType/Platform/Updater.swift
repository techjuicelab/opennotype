import OpenNoTypeCore
import Foundation
import Observation
import Sparkle

struct UpdateState: Equatable {
    var canCheck = false
    var automaticallyChecks = false
    var lastCheck: Date?
}

@MainActor
protocol UpdateBackend: AnyObject {
    var state: UpdateState { get }
    var stateChanged: (() -> Void)? { get set }
    var cycleFinished: ((Error?) -> Void)? { get set }
    var mayCheck: (() -> Bool)? { get set }
    var postponeRelaunch: ((@escaping () -> Void) -> Bool)? { get set }
    func start() throws
    func check()
    func setAutomaticallyChecks(_ enabled: Bool)
}

@MainActor @Observable
final class Updater {
    static let feedURL = URL(string: "https://github.com/techjuicelab/opennotype/releases/latest/download/appcast.xml")!
    static let releaseURL = URL(string: "https://github.com/techjuicelab/opennotype/releases/latest")!
    static let shared = Updater(info: Bundle.main.infoDictionary ?? [:], isPreview: AppLaunch.isPreview) {
        SparkleUpdateBackend(feedURL: $0)
    }

    let isPreview: Bool
    private let shortVersion: String?
    private let buildVersion: String?
    var version: String {
        let short = shortVersion ?? L("개발 버전", "Development build")
        return buildVersion.map { "\(short) (\($0))" } ?? short
    }
    let isCommunityRelease: Bool
    private(set) var isConfigured = false
    private enum ConfigurationIssue { case preview, unavailable, invalid }
    private var configurationIssue: ConfigurationIssue?
    var configurationMessage: String? {
        switch configurationIssue {
        case .preview: L("디자인 미리보기에서는 업데이트 서버에 연결하지 않습니다.", "Design previews do not connect to the update server.")
        case .unavailable: L("이 빌드에는 서명된 업데이트 채널이 아직 준비되지 않았습니다. 새 버전은 GitHub 릴리스에서 확인할 수 있습니다.", "A signed update channel is not available for this build yet. Check GitHub Releases for new versions.")
        case .invalid: L("업데이트 채널 설정이 올바르지 않아 자동 업데이트를 사용할 수 없습니다. GitHub 릴리스에서 배포 버전을 확인해 주세요.", "Automatic updates are unavailable because the update channel configuration is invalid. Check GitHub Releases for a release build.")
        case nil: nil
        }
    }
    private(set) var errorMessage: String?
    private(set) var state = UpdateState()
    private(set) var isStarted = false
    private(set) var hasDeferredInstallation = false
    @ObservationIgnored private var backend: (any UpdateBackend)?
    @ObservationIgnored private var activityIsBusy: () -> Bool = { false }
    @ObservationIgnored private var deferredInstallation: (() -> Void)?

    var isBusy: Bool { activityIsBusy() }
    var canCheck: Bool { isStarted && state.canCheck && !isBusy && !hasDeferredInstallation }
    var automaticChecks: Bool { state.automaticallyChecks }
    var lastCheck: Date? { state.lastCheck }

    init(info: [String: Any], isPreview: Bool, makeBackend: (URL) -> any UpdateBackend) {
        self.isPreview = isPreview
        isCommunityRelease = info["OpenNoTypeDistribution"] as? String == "community"
        shortVersion = info["CFBundleShortVersionString"] as? String
        buildVersion = info["CFBundleVersion"] as? String

        guard !isPreview else {
            configurationIssue = .preview
            return
        }
        guard let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty else {
            configurationIssue = .unavailable
            return
        }
        guard Self.validFeed(feed), Self.validPublicKey(key) else {
            configurationIssue = .invalid
            return
        }

        isConfigured = true
        let backend = makeBackend(Self.feedURL)
        self.backend = backend
        backend.stateChanged = { [weak self] in self?.refreshState() }
        backend.mayCheck = { [weak self] in self.map { !$0.isBusy && !$0.hasDeferredInstallation } ?? false }
        backend.postponeRelaunch = { [weak self] install in self?.postponeInstallation(install) ?? true }
        backend.cycleFinished = { [weak self] error in
            self?.deferredInstallation = nil
            self?.hasDeferredInstallation = false
            self?.errorMessage = Self.failureMessage(error)
            self?.refreshState()
        }
        do {
            try backend.start()
            isStarted = true
            refreshState()
        } catch {
            errorMessage = L("업데이트를 시작하지 못했습니다. \(error.localizedDescription)", "Could not start the updater. \(error.localizedDescription)")
        }
    }

    func check() {
        guard canCheck, let backend else { return }
        errorMessage = nil
        backend.check()
        refreshState()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isStarted, let backend, enabled != backend.state.automaticallyChecks else { return }
        // Sparkle persists this user action. Do not overwrite the stored preference at launch.
        backend.setAutomaticallyChecks(enabled)
        refreshState()
    }

    func observeActivity(_ isBusy: @escaping () -> Bool) { activityIsBusy = isBusy }

    private func postponeInstallation(_ install: @escaping () -> Void) -> Bool {
        guard isBusy else { return false }
        deferredInstallation = install
        hasDeferredInstallation = true
        return true
    }

    func resumeInstallation() {
        guard !isBusy, let install = deferredInstallation else { return }
        deferredInstallation = nil
        hasDeferredInstallation = false
        install()
    }

    private func refreshState() {
        if let backend { state = backend.state }
    }

    static func validFeed(_ value: String) -> Bool {
        guard let parts = URLComponents(string: value) else { return false }
        return parts.scheme?.lowercased() == "https"
            && parts.host?.lowercased() == "github.com"
            && parts.user == nil && parts.password == nil && parts.port == nil
            && parts.percentEncodedPath == feedURL.path
            && parts.query == nil && parts.fragment == nil
    }

    static func validPublicKey(_ value: String) -> Bool {
        guard let decoded = Data(base64Encoded: value), decoded.count == 32,
              decoded != Data(repeating: 0, count: 32) else { return false }
        return decoded.base64EncodedString() == value
    }

    static func failureMessage(_ error: Error?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain,
           [Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue),
            Int(SUError.installationAuthorizeLaterError.rawValue)].contains(nsError.code) {
            return nil
        }
        return L("업데이트 확인 또는 설치를 완료하지 못했습니다. \(error.localizedDescription)", "Could not complete the update check or installation. \(error.localizedDescription)")
    }
}

@MainActor
final class SparkleUpdateBackend: NSObject, UpdateBackend, SPUUpdaterDelegate {
    private let feedURL: URL
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    var stateChanged: (() -> Void)?
    var cycleFinished: ((Error?) -> Void)?
    var mayCheck: (() -> Bool)?
    var postponeRelaunch: ((@escaping () -> Void) -> Bool)?

    var state: UpdateState {
        let updater = controller.updater
        return UpdateState(canCheck: updater.canCheckForUpdates,
                           automaticallyChecks: updater.automaticallyChecksForUpdates,
                           lastCheck: updater.lastUpdateCheckDate)
    }

    init(feedURL: URL) {
        self.feedURL = feedURL
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.stateChanged?() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.stateChanged?() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.stateChanged?() }
            }
        ]
    }

    func start() throws { try controller.updater.start() }
    func check() { controller.checkForUpdates(nil) }
    func setAutomaticallyChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }

    // Pin the validated channel instead of inheriting a legacy SUFeedURL in UserDefaults.
    func feedURLString(for updater: SPUUpdater) -> String? { feedURL.absoluteString }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard mayCheck?() == true else {
            throw NSError(domain: "app.opennotype.updater", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("녹음이나 문장 처리가 끝난 뒤 업데이트를 확인해 주세요.", "Check for updates after recording or text processing finishes.")])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeRelaunch?(installHandler) ?? true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        cycleFinished?(error)
    }
}
