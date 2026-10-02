import SwiftUI
import OpenNoTypeCore

struct UpdateSettingsView: View {
    @Bindable var updater: Updater

    var body: some View {
        Surface(L("앱 업데이트", "App updates")) {
            LabeledContent(L("현재 버전", "Current version"), value: updater.version)
            if updater.isCommunityRelease {
                Label(L("커뮤니티 배포 · Apple 공증 없음", "Community release · Not notarized by Apple"), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("업데이트 확인…", "Check for updates…"), systemImage: "arrow.triangle.2.circlepath") { updater.check() }
                    .disabled(!updater.canCheck)
                Link(L("GitHub 릴리스 보기", "View GitHub releases"), destination: Updater.releaseURL)
                    .disabled(updater.isPreview)
            }
            Toggle(L("새 버전 자동 확인", "Automatically check for updates"), isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
                .disabled(!updater.isStarted)
            Text(L("자동 확인을 켜면 새 버전이 있을 때 알려드립니다. 설치는 업데이트 안내 창에서 선택할 수 있습니다.", "Automatic checks notify you when a new version is available. Choose whether to install it in the update dialog."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if updater.isBusy {
                Text(L("녹음과 문장 처리가 끝나면 업데이트를 확인하거나 설치할 수 있습니다.", "You can check for or install updates after recording and text processing finish."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if updater.hasDeferredInstallation {
                Text(L("진행 중인 작업을 보호하기 위해 설치를 잠시 미뤘습니다. 작업이 끝난 뒤 다시 실행을 선택해 주세요.", "Installation was deferred to protect your current work. Choose to relaunch after it finishes."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button(L("업데이트 설치하고 다시 실행", "Install update and relaunch")) { updater.resumeInstallation() }
                    .disabled(updater.isBusy)
            }
            if let date = updater.lastCheck {
                LabeledContent(L("마지막 확인", "Last checked")) { Text(date, format: .dateTime.year().month().day().hour().minute().locale(AppLocalization.shared.language.locale)) }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if updater.isStarted {
                Text(L("아직 업데이트를 확인하지 않았습니다.", "Updates have not been checked yet."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let message = updater.configurationMessage {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = updater.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
