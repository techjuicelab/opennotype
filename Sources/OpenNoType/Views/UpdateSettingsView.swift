import SwiftUI

struct UpdateSettingsView: View {
    @Bindable var updater: Updater

    var body: some View {
        Surface("앱 업데이트") {
            LabeledContent("현재 버전", value: updater.version)
            if updater.isCommunityRelease {
                Label("커뮤니티 배포 · Apple 공증 없음", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                Button("업데이트 확인…", systemImage: "arrow.triangle.2.circlepath") { updater.check() }
                    .disabled(!updater.canCheck)
                Link("GitHub 릴리스 보기", destination: Updater.releaseURL)
                    .disabled(updater.isPreview)
            }
            Toggle("새 버전 자동 확인", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
                .disabled(!updater.isStarted)
            Text("자동 확인을 켜면 새 버전이 있을 때 알려드립니다. 설치는 업데이트 안내 창에서 선택할 수 있습니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if updater.isBusy {
                Text("녹음과 문장 처리가 끝나면 업데이트를 확인하거나 설치할 수 있습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if updater.hasDeferredInstallation {
                Text("진행 중인 작업을 보호하기 위해 설치를 잠시 미뤘습니다. 작업이 끝난 뒤 다시 실행을 선택해 주세요.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("업데이트 설치하고 다시 실행") { updater.resumeInstallation() }
                    .disabled(updater.isBusy)
            }
            if let date = updater.lastCheck {
                LabeledContent("마지막 확인") { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if updater.isStarted {
                Text("아직 업데이트를 확인하지 않았습니다.")
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
