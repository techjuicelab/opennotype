import OpenNoTypeCore

enum DictationTranslationExamples {
    // The source stays Korean in either interface language so the translation can be compared.
    static let source = "혹시 시간 괜찮으시면 오늘 안으로 초안 한번 봐 주실 수 있을까요? 큰 방향은 괜찮은 것 같은데 첫 부분이 조금 딱딱한 것 같아서요. 12개 항목은 그대로 두고, 아직 확정된 건 아니라서 승인 전에는 공유하지 말아 주세요."

    static func result(for language: DictationOutputLanguage) -> String {
        switch language {
        case .original, .korean:
            "혹시 시간 괜찮으시면 오늘 안으로 초안을 한번 봐 주실 수 있을까요? 큰 방향은 괜찮은 것 같은데, 첫 부분이 조금 딱딱한 것 같아서요. 12개 항목은 그대로 두고, 아직 확정된 것은 아니라서 승인 전에는 공유하지 말아 주세요."
        case .english:
            "If you have a chance, could you take a look at the draft by the end of today? I think the overall direction works, but the opening feels a little stiff. Please keep all 12 items as they are, and don't share it until it's approved, since it hasn't been finalized yet."
        case .japanese:
            "お時間があれば、今日中にドラフトに目を通していただけますか。全体の方向性はよいと思うのですが、書き出しが少し硬い印象です。12項目はそのまま残してください。まだ確定していないので、承認が出るまでは共有しないでください。"
        }
    }
}
