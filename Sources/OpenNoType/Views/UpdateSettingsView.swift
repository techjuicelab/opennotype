import SwiftUI
import OpenNoTypeCore

struct UpdateSettingsView: View {
    @Bindable var updater: Updater
    var isEditable: Bool = true
    var embedded = false
    var body: some View {
        if embedded { rows } else { SettingsPanel(L("업데이트", "Updates")) { rows } }
    }

    private var lastCheckText: String {
        guard let date = updater.lastCheck else { return L("아직 확인하지 않았습니다.", "Not checked yet.") }
        return L("마지막 확인 ", "Last checked ") + date.formatted(.dateTime.year().month().day().hour().minute().locale(AppLocalization.shared.language.locale))
    }

    @ViewBuilder private var rows: some View {
        SettingsRows {
            SettingsRow(L("현재 버전", "Current version"), detail: lastCheckText,
                        help: updater.isCommunityRelease
                        ? L("커뮤니티 배포이며 Apple 공증이 없습니다. 업데이트는 기존 공개 피드와 서명 검증 정책을 사용합니다.", "Community release without Apple notarization. Updates use the existing public feed and signature-verification policy.") : nil,
                        state: updater.isBusy ? L("녹음·문장 처리 후 확인 가능", "Available after recording and processing") : nil) {
                Text(updater.version).font(AppTypography.caption.monospacedDigit()).foregroundStyle(AppTheme.textSecondary)
                Button(L("새 버전 확인", "Check for updates")) { updater.check() }.disabled(!isEditable || !updater.canCheck)
            }
            SettingsRow(L("새 버전 자동 확인", "Automatically check for updates"), help: L("새 버전을 알려 주며 자동 설치를 켜지는 않습니다. 설치는 안내 창에서 선택합니다.", "Notifies you of new versions without enabling automatic installation. Choose installation in the update dialog.")) {
                Toggle(L("새 버전 자동 확인", "Automatically check for updates"), isOn: Binding(get: { updater.automaticChecks }, set: { if isEditable { updater.setAutomaticChecks($0) } }))
                    .labelsHidden().toggleStyle(.switch).disabled(!isEditable || !updater.isStarted)
            }
            SettingsRow(L("공개 릴리스", "Public releases")) {
                Link(destination: Updater.releaseURL) { Label(L("GitHub 릴리스", "GitHub releases"), systemImage: "arrow.up.right").labelStyle(TrailingIconLabelStyle()) }
                    .disabled(!isEditable || updater.isPreview)
            }
            if updater.hasDeferredInstallation {
                SettingsRow(L("지연된 업데이트", "Deferred update"), state: L("진행 중인 작업 보호 · 작업 종료 후 재실행", "Protecting your work · Relaunch after it finishes")) {
                    Button(L("설치하고 다시 실행", "Install and relaunch")) { updater.resumeInstallation() }.disabled(!isEditable || updater.isBusy)
                }
            }
        }
        if let message = updater.configurationMessage {
            Label(message, systemImage: "info.circle").font(AppTypography.caption).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        if let error = updater.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle").font(AppTypography.caption).foregroundStyle(AppTheme.warm).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}
