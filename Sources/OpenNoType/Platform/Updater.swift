import Foundation
import AppKit
import Sparkle

@MainActor
final class Updater {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?
    private init() {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              feed.hasPrefix("https://"),
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    func check() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = "개발 미리보기 버전입니다"
            alert.informativeText = "서명된 정식 배포 채널이 준비되면 자동 업데이트가 활성화됩니다. 이 빌드에는 아직 업데이트 피드가 설정되지 않았습니다."
            alert.runModal(); return
        }
        controller.checkForUpdates(nil)
    }
}
