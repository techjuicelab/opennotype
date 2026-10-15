import AppKit
import OpenNoTypeCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryWorkspaceView: View {
    @Bindable var model: AppModel
    var showsRecovery = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            HStack(alignment: .center, spacing: 16) {
                AppPageHeader(L("기록", "History"), help: L("텍스트 기록은 설정한 기간 동안 이 Mac에 암호화해 보관합니다. 실패 녹음은 별도로 최대 24시간 보관하며 성공하거나 만료하면 삭제합니다.", "Text history is encrypted on this Mac for the configured retention period. Failed recordings are kept separately for up to 24 hours and deleted after success or expiry."))
                Spacer(minLength: 12)
                Picker(L("기록 분류", "History category"), selection: Binding(get: { showsRecovery }, set: { model.page = $0 ? .recovery : .history })) {
                    Text(L("처리 기록", "Text history")).tag(false)
                    Text(L("녹음 복구", "Recording recovery")).tag(true)
                }.pickerStyle(.segmented).frame(width: 260)
            }
            if showsRecovery { RecoveryView(model: model) }
            else { HistoryView(model: model) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var confirmsDeletion = false
    @State private var deleting = false

    private var matches: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.history.filter {
            query.isEmpty || $0.resultText.localizedCaseInsensitiveContains(query) || $0.originalText.localizedCaseInsensitiveContains(query)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    private var selectedEntry: HistoryEntry? { matches.first { $0.id == selectedID } }
    private var editable: Bool { !AppLaunch.isPreview && !model.preferencesRecoveryRequired && model.startupState == .ready }
    private var retention: String {
        model.preferences.historyEnabled
            ? (model.preferences.retentionDays == -1 ? L("직접 삭제할 때까지 보관", "Kept until deleted") : L("보관 \(model.preferences.retentionDays)일", "Kept for \(model.preferences.retentionDays) days"))
            : L("새 기록 저장 꺼짐", "New history is off")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DataSearchField(text: $search, prompt: L("결과와 원문 검색", "Search results and transcripts"))
                Text(L("\(matches.count)개", "\(matches.count) items")).font(AppTypography.caption).foregroundStyle(.secondary).fixedSize()
                Menu {
                    Button(L("모든 기록 삭제…", "Delete all history…"), role: .destructive) { confirmsDeletion = true }
                        .disabled(model.history.isEmpty || deleting || !editable)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 32, height: 32) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(L("기록 더보기", "More history actions"))
            }
            Text(retention).font(AppTypography.caption).foregroundStyle(.secondary)
            if matches.isEmpty {
                DataEmptyState(icon: search.isEmpty ? "clock" : "magnifyingglass", title: search.isEmpty ? L("아직 보관한 기록이 없어요", "No saved records yet") : L("일치하는 기록이 없어요", "No matching records"), detail: search.isEmpty ? L("말을 글로 옮기면 다시 확인하고 복사할 수 있어요.", "Turn speech into text to review and copy it here.") : L("다른 단어나 짧은 표현으로 검색해 보세요.", "Try another word or a shorter search."))
                    .frame(maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedID) {
                        ForEach(matches) { entry in
                            historyRow(entry).tag(entry.id)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                    .accessibilityLabel(L("처리 기록 목록", "Text history list"))
                    ScrollView {
                        if let entry = selectedEntry {
                            HistoryEntryCard(model: model, entry: entry, deleting: deleting || !editable) { delete(entry) }
                                .id(entry.id).padding(.leading, 12).padding(.trailing, 4).padding(.bottom, 12)
                        } else {
                            DataEmptyState(icon: "text.alignleft", title: L("기록을 선택해 주세요", "Select a record"), detail: L("목록에서 한 결과를 확인할 수 있어요.", "Choose a result from the list."))
                        }
                    }.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reconcileSelection)
        .onChange(of: model.history.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: matches.map(\.id)) { _, _ in if selectedID == nil { selectedID = matches.first?.id } }
        .confirmationDialog(L("보관한 기록 \(model.history.count)개를 모두 삭제할까요?", "Delete all \(model.history.count) saved records?"), isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button(L("모든 기록 삭제", "Delete all records"), role: .destructive) { delete(nil) }
            Button(L("취소", "Cancel"), role: .cancel) { }
        } message: { Text(L("이 Mac의 기록과 학습한 Jev 오류 유형을 삭제하고, 진행 중인 검토와 진단도 지웁니다. 개인 사전과 아직 보관 중인 실패 녹음은 유지됩니다.", "Deletes history and learned Jev error categories on this Mac, and clears pending reviews and diagnostics. Your dictionary and saved failed recordings are kept.")) }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.resultText).font(AppTypography.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(entry.skippedTextProcessing == true && entry.effectiveMode == .dictation ? L("바로 입력", "Direct input") : entry.effectiveMode.title)
                Text("·")
                Text(entry.createdAt, format: .dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale))
            }.font(AppTypography.caption).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.vertical, 6).frame(minHeight: 56, alignment: .leading)
    }
    private func reconcileSelection() {
        // Keep a filtered-out selection so clearing search restores the same record.
        if let selectedID, model.history.contains(where: { $0.id == selectedID }) { return }
        selectedID = matches.first?.id
    }
    private func delete(_ entry: HistoryEntry?) {
        guard editable, !deleting else { return }
        deleting = true
        Task { await model.deleteHistory(entry); deleting = false }
    }
}

private struct HistoryEntryCard: View {
    @Bindable var model: AppModel
    let entry: HistoryEntry
    let deleting: Bool
    let delete: () -> Void

    private var originalTitle: String { entry.mode == .rewrite ? L("음성으로 말한 수정 지시", "Spoken rewrite instructions") : L("인식 원문", "Transcript") }
    private var translationLanguage: String? {
        guard let purpose = reviewPurpose, case .translation(let language) = purpose else { return nil }
        return language
    }
    private var reviewPurpose: DecisionReviewPurpose? { model.historyReviewPurpose(for: entry) }
    private var isQuickDictation: Bool { entry.mode == .dictation && entry.effectiveMode == .dictation && entry.skippedTextProcessing == true }

    var body: some View {
        Surface {
            HStack(spacing: 9) {
                Label(isQuickDictation ? L("빠른 로컬 받아쓰기", "Quick on-device dictation")
                      : entry.mode == .dictation && entry.effectiveMode == .translation
                      ? L("받아쓰기 · 번역", "Dictation · Translation") : entry.effectiveMode.title,
                      systemImage: modeIcon(entry.effectiveMode))
                    .font(AppTypography.caption.weight(.medium)).foregroundStyle(AppTheme.accentForeground)
                Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().locale(AppLocalization.shared.language.locale))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if let translationLanguage {
                Text(L("당시 출력 언어: \(translationLanguage)", "Captured output language: \(translationLanguage)"))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
            if entry.mode == .prompt { PromptCompositionReviewSummaryView(summary: entry.promptReviewSummary) }
            if isQuickDictation {
                HStack {
                    Text(L("로컬 인식 원문 · AI 문장 정리 없음", "Local transcript · No AI cleanup")).font(AppTypography.caption).foregroundStyle(.secondary)
                    OptionHelp(title: L("바로 입력 기록", "Direct-input history"), message: L("이 Mac에서 인식한 원문을 AI 문장 정리 없이 입력한 기록입니다. Jev 검토와 AI 다시 처리는 직접 요청할 때만 원문을 외부 서비스로 보냅니다. 원음 그대로의 표현이나 정확성을 보장하는 기능은 아닙니다.", "This transcript was entered locally without AI cleanup. Explicit Jev review and AI reprocessing send its transcript to an external service. This does not guarantee literal fidelity or recognition accuracy."))
                }
            }
            textBlock(L("보관된 결과", "Saved result"), text: entry.resultText,
                      copyLabel: entry.mode == .prompt ? L("프롬프트 복사", "Copy prompt") : L("결과 복사", "Copy result"),
                      copyDisabled: entry.mode == .prompt && entry.promptReviewSummary?.deliveryDisposition == .blocked, primary: true)
            DisclosureGroup(entry.mode == .rewrite ? L("음성 수정 지시 확인", "View spoken rewrite instructions") : L("인식 원문과 비교", "Compare with transcript")) {
                VStack(alignment: .leading, spacing: 8) {
                    textBlock(originalTitle, text: entry.originalText, copyLabel: L("\(originalTitle) 복사", "Copy \(originalTitle)"))
                    if entry.originalText == entry.resultText {
                        Text(L("인식 원문과 보관된 결과가 같아요.", "The transcript and saved result are identical.")).font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
            }.font(AppTypography.caption)
            DisclosureGroup(L("더보기", "More")) {
            if let reviewPurpose {
                JevReviewRequestButton(model: model, title: L("보관된 결과를 Jev로 검토…", "Review saved result with Jev…"),
                                       targetTitle: L("이 기록의 인식 원문과 보관된 결과", "This record’s transcript and saved result"),
                                       requestIdentity: entry.id.uuidString, purpose: reviewPurpose, disabled: deleting) {
                    model.reviewHistory(entry)
                }
                if let target = model.decisionReviewTarget, target.kind == .history, target.sourceHistoryID == entry.id {
                    JevReviewView(model: model, target: target)
                }
            } else if entry.mode == .translation {
                Text(L("당시 번역 언어가 없거나 확인할 수 없어 직접 검토할 수 없습니다. 현재 설정으로 다시 처리한 미리보기를 검토할 수 있습니다.", "The captured translation language is missing or invalid, so this saved result cannot be reviewed directly. You can reprocess it with current settings and review that preview."))
                    .font(AppTypography.caption).foregroundStyle(.secondary).lineSpacing(3)
            }
            if let reason = model.historyReprocessingUnavailableReason(for: entry) {
                Text(reason).font(AppTypography.caption).foregroundStyle(.secondary)
            } else {
                DisclosureGroup(L("AI로 문장 다시 처리", "Reprocess text with AI")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.historyReprocessingSettings(for: entry))
                            .font(AppTypography.caption.weight(.medium)).textSelection(.enabled)
                        HStack {
                            Text(L("인식 원문 전송 · 추가 API 비용", "Transcript sent · Additional API cost")).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                            OptionHelp(title: L("AI 다시 처리", "AI reprocessing"), message: L("인식 원문을 현재 제공자에 보내 문장만 다시 처리합니다. 기존 결과는 그대로 보관하며 새 결과는 별도 보관하지 않는 미리보기입니다. 이 기록의 앱에 지정된 현재 프로필을 사용하며 당시 입력창의 주변 문맥은 저장되어 있지 않습니다.", "Sends the transcript to the current provider for text-only reprocessing. The saved result is retained and the new preview is not stored separately. Uses the current profile assigned to this record's app; surrounding text-field context was not saved."))
                        }
                        if entry.mode == .translation && translationLanguage == nil {
                            Text(L("당시 번역 언어가 없거나 확인할 수 없어 위에 표시된 현재 번역 언어를 사용해요.", "The captured translation language is missing or invalid, so the current language shown above is used."))
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                        } else if entry.effectiveMode == .translation {
                            Text(L("위에 표시된 현재 출력 언어로 다시 처리합니다. 당시 번역 언어와 다를 수 있습니다.", "Reprocesses in the current output language shown above, which may differ from the captured translation language."))
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                        }
                        Button(L("원문 다시 처리", "Reprocess transcript"), systemImage: "arrow.clockwise") { model.reprocessHistory(entry) }
                            .disabled(model.isBusy || deleting)
                    }.padding(.top, 8)
                }.font(AppTypography.caption)
            }
                Button(L("이 기록 삭제", "Delete this record"), role: .destructive, action: delete).disabled(deleting)
            }.font(AppTypography.body)
            if let preview = model.historyReprocessing, preview.entryID == entry.id {
                Divider()
                HStack {
                    Label(L("다시 처리한 결과 · 미리보기", "Reprocessed result · Preview"), systemImage: "text.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(preview.isProcessing ? L("취소", "Cancel") : L("미리보기 닫기", "Close preview")) { model.dismissHistoryReprocessing() }
                        .buttonStyle(.borderless)
                }
                Text(preview.settingsDescription).font(AppTypography.caption).foregroundStyle(.secondary)
                if preview.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("문장을 다시 처리하고 있어요…", "Reprocessing text…")).font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                } else if let result = preview.result {
                    if entry.mode == .prompt { PromptCompositionReviewSummaryView(summary: preview.promptReviewSummary) }
                    textBlock(preview.translationRefinement?.held == true ? L("번역 초안", "Draft translation") : L("새 결과", "New result"),
                              text: result, copyLabel: entry.mode == .prompt ? L("프롬프트 복사", "Copy prompt")
                                : preview.translationRefinement?.held == true ? L("초안 복사", "Copy draft") : L("새 결과 복사", "Copy new result"),
                              copyDisabled: entry.mode == .prompt && preview.promptReviewSummary?.deliveryDisposition == .blocked, primary: true)
                    if let error = preview.error {
                        Text(error).font(AppTypography.caption).foregroundStyle(AppTheme.warm).textSelection(.enabled)
                    }
                    Text(L("미리보기는 별도로 보관하지 않아요. 필요한 결과를 복사해 주세요.", "This preview is not saved separately. Copy the result if you need it."))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                    if let reviewTarget = preview.reviewTarget {
                        JevReviewRequestButton(model: model, title: L("이 미리보기를 Jev로 검토…", "Review this preview with Jev…"),
                                               targetTitle: L("이 기록의 인식 원문과 다시 처리한 미리보기", "This record’s transcript and reprocessed preview"),
                                               requestIdentity: preview.id.uuidString, purpose: reviewTarget.purpose, disabled: deleting) {
                            model.reviewHistoryPreview()
                        }
                        if let target = model.decisionReviewTarget, target.kind == .reprocessed,
                           target.sourceHistoryID == entry.id, target.previewID == preview.id {
                            JevReviewView(model: model, target: target)
                        }
                    }
                } else if let error = preview.error {
                    Text(error).font(AppTypography.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                if let refinement = preview.translationRefinement {
                    TranslationRefinementResultView(refinement: refinement)
                }
            }
            HStack(spacing: 8) {
                Text(isQuickDictation ? L("이 Mac · AI 문장 처리 없음", "This Mac · No AI text processing") : entry.provider.displayName)
                if let bundleID = entry.sourceBundleID { Text("·"); Text(bundleID).lineLimit(1).truncationMode(.middle) }
            }.font(AppTypography.caption).foregroundStyle(.tertiary)
        }
    }

    private func textBlock(_ title: String, text: String, copyLabel: String, copyDisabled: Bool = false, primary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(AppTypography.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(copyLabel, systemImage: "doc.on.doc") { copyText(text, model: model, label: title) }
                    .buttonStyle(AppActionButtonStyle(primary: primary)).disabled(copyDisabled)
            }
            Text(text).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DictionaryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var editor: DictionaryEditorDraft?
    @State private var working = false
    @State private var imported: [DictionaryEntry] = []
    @State private var confirmsImport = false

    private var editable: Bool { !AppLaunch.isPreview && !model.preferencesRecoveryRequired && model.startupState == .ready }
    private var canPresentEditor: Bool { !working && (editable || AppLaunch.isPreview && !model.preferencesRecoveryRequired) }
    private var matches: [DictionaryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.dictionary.filter { query.isEmpty || $0.spoken.localizedCaseInsensitiveContains(query) || $0.written.localizedCaseInsensitiveContains(query) }
            .sorted { $0.written.localizedStandardCompare($1.written) == .orderedAscending }
    }
    private var replacementCount: Int {
        imported.filter { item in model.dictionary.contains { $0.spoken.caseInsensitiveCompare(item.spoken) == .orderedSame } }.count
    }
    private var dictionaryHelp: String {
        L("말하거나 인식된 표기와 원하는 표기를 한 쌍으로 등록합니다. 각 항목은 1~100자입니다. 음성 인식 참고 단어는 최대 24개, 문장 정리는 최대 200개를 최근 교정·관련성에 따라 선택합니다. 제공자와 모델에 따라 힌트 지원이 다르며 모든 표기의 인식 성공을 보장하지 않습니다.", "Add a spoken or recognized spelling and your preferred spelling as a pair. Each field is 1–100 characters. Speech recognition selects up to 24 terms and text cleanup up to 200 based on recent corrections and relevance. Hint support varies by provider and model, and does not guarantee recognition.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            HStack(spacing: 12) {
                AppPageHeader(L("개인 사전", "Dictionary"), help: dictionaryHelp)
                Spacer(minLength: 12)
                Button(L("단어 추가…", "Add word…"), systemImage: "plus") { guard canPresentEditor else { return }; editor = .init() }
                    .buttonStyle(AppActionButtonStyle(primary: true)).disabled(!canPresentEditor)
            }
            HStack(spacing: 12) {
                Picker(L("사전 분류", "Dictionary category"), selection: $model.dictionarySection) {
                    ForEach(DictionarySection.allCases) { item in Text(item.title).tag(item) }
                }.pickerStyle(.segmented).frame(maxWidth: 360)
                if model.learningCandidate != nil {
                    Button(L("확인할 교정 1개", "1 correction to review")) { model.dictionarySection = .learning }
                        .buttonStyle(.borderless).font(AppTypography.caption)
                }
            }
            switch model.dictionarySection {
            case .words: wordsSection
            case .learning: learningSection
            case .names: JevNameCatalogView(model: model)
            }
        }
        .sheet(item: $editor) { draft in DictionaryEntryEditor(model: model, draft: draft) }
        .onChange(of: model.preferencesRecoveryRequired) { _, required in
            if required { editor = nil; confirmsImport = false; imported = [] }
        }
        .confirmationDialog(L("사전 \(imported.count)개를 가져올까요?", "Import \(imported.count) dictionary entries?"), isPresented: $confirmsImport, titleVisibility: .visible) {
            Button(L("사전 가져오기", "Import dictionary")) { applyImport() }
            Button(L("취소", "Cancel"), role: .cancel) { imported = [] }
        } message: {
            Text(replacementCount == 0 ? L("기존 사전을 유지하면서 새 항목을 추가합니다.", "Adds new entries while keeping your existing dictionary.") : L("같은 인식 표기가 있는 \(replacementCount)개 항목은 가져온 표기로 바뀝니다. 나머지 사전은 유지됩니다.", "Replaces \(replacementCount) entries with matching recognized spellings. All other entries are kept."))
        }
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DataSearchField(text: $search, prompt: L("단어와 표기 검색", "Search words and spellings"))
                Text(L("\(matches.count)개", "\(matches.count) items")).font(AppTypography.caption).foregroundStyle(.secondary).fixedSize()
                Menu {
                    Button(L("JSON 파일 가져오기…", "Import JSON file…"), systemImage: "square.and.arrow.down", action: importDictionary)
                    Button(L("JSON 파일 내보내기…", "Export JSON file…"), systemImage: "square.and.arrow.up", action: exportDictionary).disabled(model.dictionary.isEmpty)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 32, height: 32) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(working || !editable).accessibilityLabel(L("사전 더보기", "More dictionary actions"))
            }
            if matches.isEmpty {
                DataEmptyState(icon: "character.book.closed", title: search.isEmpty ? L("아직 등록한 단어가 없어요", "No words yet") : L("일치하는 단어가 없어요", "No matching words"), detail: search.isEmpty ? L("자주 쓰는 이름·용어부터 추가해 보세요.", "Start with names and terms you use often.") : L("다른 표기로 검색하거나 새 단어를 등록해 보세요.", "Search another spelling or add a new word."))
            } else {
                Surface {
                    HStack(spacing: 16) {
                        Text(L("말하거나 인식된 표기", "Spoken or recognized spelling")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L("원하는 표기", "Preferred spelling")).frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 64, height: 1)
                    }.font(AppTypography.caption).foregroundStyle(.secondary)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            dictionaryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.decisionProposalStatus != nil || model.canUndoDecisionDictionarySave {
                Surface(L("Jev 제안에서 저장한 표기", "Spellings saved from Jev suggestions")) { JevDictionaryUndoView(model: model) }
            }
            Surface {
                SettingsRow(L("고친 표기 자동 학습", "Learn corrected spellings"),
                    help: L("입력 완료가 확인된 받아쓰기의 같은 입력창에서 30초 동안 교정을 확인하고 약 3초 유지된 좁고 명확한 표기만 기억합니다. 대소문자·일부 고유명사 철자가 대상이며 한글↔영문과 일반 단어 변경은 직접 검토해야 합니다. 수치·버전·날짜·문장 전체 변경은 자동 등록하지 않습니다. 기록 저장과 별개이며 끄면 새 관찰·등록을 멈추고 기존 사전은 유지합니다.", "Observes confirmed dictation in the same field for 30 seconds and learns narrow, clear spelling edits that remain for about 3 seconds. Capitalization and some proper names qualify; Korean–English spellings and ordinary word changes need review. Numbers, versions, dates and whole-sentence changes are not learned automatically. This is separate from history; turning it off stops new observation and learning while retaining existing entries.")) {
                    Text(model.preferences.automaticLearningEnabled ? L("켜짐", "On") : L("꺼짐", "Off"))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                    Button(L("학습 설정…", "Learning settings…")) { model.openSettings(.privacy) }
                }
                if model.canUndoLastLearning {
                    Button(L("마지막 자동 학습 되돌리기", "Undo last learned spelling"), systemImage: "arrow.uturn.backward") {
                        guard editable, !working else { return }
                        working = true
                        Task { await model.undoLastLearning(); working = false }
                    }.disabled(working || !editable)
                }
            }
            if let candidate = model.learningCandidate {
                Surface(L("확인할 교정", "Correction to review")) {
                    HStack {
                        Text(L("아직 사전에 저장하지 않았습니다", "Not saved to your dictionary")).font(AppTypography.caption).foregroundStyle(.secondary)
                        Spacer()
                        OptionHelp(title: L("교정 후보", "Correction candidate"), message: L("자동 등록하기 어려운 표기 교정은 직접 확인합니다. 검토 결과만으로 사전에 저장하거나 현재 입력한 글을 바꾸지 않습니다.", "Review spelling edits that cannot be learned automatically. Review alone does not save a dictionary entry or change the text already entered."))
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) { candidateText(L("입력한 내용", "Original text"), text: candidate.originalText); candidateText(L("바꾼 내용", "Edited text"), text: candidate.editedText) }
                        VStack(alignment: .leading, spacing: 12) { candidateText(L("입력한 내용", "Original text"), text: candidate.originalText); candidateText(L("바꾼 내용", "Edited text"), text: candidate.editedText) }
                    }
                    JevCorrectionReviewView(model: model, candidate: candidate)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { candidateActions(candidate) }
                        VStack(alignment: .leading, spacing: 8) { candidateActions(candidate) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func candidateActions(_ candidate: LearningCandidate) -> some View {
        if let proposed = CorrectionLearner.reviewProposal(original: candidate.originalText, edited: candidate.editedText) {
            Button(L("표기 확인…", "Review spelling…"), systemImage: "pencil") { editor = .init(spoken: proposed.spoken, written: proposed.written) }.disabled(!editable || working)
        }
        Button(L("단어 직접 추가…", "Add a word…"), systemImage: "plus") { editor = .init() }.disabled(!editable || working)
        Button(L("검토하지 않기", "Dismiss review")) {
            guard editable, !working else { return }
            working = true
            Task { await model.dismissLearningCandidate(); working = false }
        }.disabled(!editable || working).foregroundStyle(.secondary)
    }
    private func candidateText(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AppTypography.caption).foregroundStyle(.secondary)
            Text(text).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func dictionaryRow(_ entry: DictionaryEntry) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(entry.spoken).font(AppTypography.body).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.written).font(AppTypography.body.weight(.medium)).textSelection(.enabled)
                if entry.learned { Text(L("교정에서 학습", "Learned from a correction")).font(AppTypography.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                Button { guard canPresentEditor else { return }; editor = .init(entry: entry, spoken: entry.spoken, written: entry.written) } label: { Image(systemName: "pencil").frame(width: 32, height: 32) }
                    .buttonStyle(.borderless).disabled(!canPresentEditor).accessibilityLabel(L("\(entry.written) 수정", "Edit \(entry.written)"))
                Button(role: .destructive) {
                    guard editable, !working else { return }
                    working = true
                    Task { await model.deleteDictionaryEntry(entry); working = false }
                } label: { Image(systemName: "trash").frame(width: 32, height: 32) }
                    .buttonStyle(.borderless).disabled(working || !editable).accessibilityLabel(L("\(entry.written) 삭제", "Delete \(entry.written)"))
            }.frame(width: 64)
        }.frame(minHeight: entry.learned ? 56 : 44).padding(.vertical, 2)
    }

    private func exportDictionary() {
        guard editable, !working else { return }
        let panel = NSSavePanel()
        panel.title = L("개인 사전 내보내기", "Export dictionary")
        panel.nameFieldStringValue = L("OpenNoType-사전.json", "OpenNoType-dictionary.json")
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message = L("사전의 단어와 표기를 JSON 파일로 저장합니다. 내보낸 파일은 암호화되지 않습니다.", "Saves dictionary words and spellings to a JSON file. The exported file is not encrypted.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = DictionaryTransferDocument(version: 1, entries: model.dictionary.map { .init(spoken: $0.spoken, written: $0.written) })
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            model.notice = L("사전 \(document.entries.count)개를 내보냈습니다.", "Exported \(document.entries.count) dictionary entries.")
        } catch { model.error = L("사전을 내보내지 못했습니다. \(error.localizedDescription)", "Could not export the dictionary. \(error.localizedDescription)") }
    }

    private func importDictionary() {
        guard editable, !working else { return }
        let panel = NSOpenPanel()
        panel.title = L("개인 사전 가져오기", "Import dictionary")
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw DictionaryTransferError.tooLarge }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= 1_048_576 else { throw DictionaryTransferError.tooLarge }
            let decoder = JSONDecoder()
            let entries: [DictionaryTransferEntry]
            if let document = try? decoder.decode(DictionaryTransferDocument.self, from: bytes) {
                guard document.version == 1 else { throw DictionaryTransferError.unsupportedVersion }
                entries = document.entries
            } else { entries = try decoder.decode([DictionaryTransferEntry].self, from: bytes) }
            guard !entries.isEmpty, entries.count <= 5_000 else { throw DictionaryTransferError.invalidEntries }
            var unique: [String: DictionaryEntry] = [:]
            for entry in entries {
                let spoken = entry.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                let written = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spoken.isEmpty, !written.isEmpty, spoken.count <= 100, written.count <= 100 else { throw DictionaryTransferError.invalidEntries }
                unique[spoken.lowercased()] = DictionaryEntry(spoken: spoken, written: written)
            }
            imported = unique.values.sorted { $0.spoken.localizedStandardCompare($1.spoken) == .orderedAscending }
            confirmsImport = true
        } catch { model.error = L("사전을 가져오지 못했습니다. \(error.localizedDescription)", "Could not import the dictionary. \(error.localizedDescription)") }
    }

    private func applyImport() {
        guard editable, !working else { return }
        working = true
        let entries = imported
        Task {
            if await model.importDictionary(entries) { model.notice = L("사전 \(entries.count)개를 가져왔습니다.", "Imported \(entries.count) dictionary entries.") }
            imported = []; working = false
        }
    }
}

private struct DictionaryEditorDraft: Identifiable {
    let id = UUID()
    var entry: DictionaryEntry? = nil
    var spoken = ""
    var written = ""
}

private struct DictionaryEntryEditor: View {
    @Bindable var model: AppModel
    let draft: DictionaryEditorDraft
    @Environment(\.dismiss) private var dismiss
    @State private var spoken: String
    @State private var written: String
    @State private var working = false
    @FocusState private var focusedField: Field?
    private enum Field { case spoken, written }

    init(model: AppModel, draft: DictionaryEditorDraft) {
        self.model = model
        self.draft = draft
        _spoken = State(initialValue: draft.spoken)
        _written = State(initialValue: draft.written)
    }
    private var editable: Bool { !AppLaunch.isPreview && !model.preferencesRecoveryRequired && model.startupState == .ready }
    private var canSave: Bool {
        editable && !working && !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && spoken.count <= 100 && written.count <= 100
            && (draft.entry == nil || model.dictionary.contains { $0.id == draft.entry?.id })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppPageHeader(draft.entry == nil ? L("단어 추가", "Add word") : L("단어 수정", "Edit word"), help: L("말하거나 인식된 표기와 원하는 표기를 한 쌍으로 등록합니다. 각 필드는 1~100자입니다. 등록한 사전은 음성 인식과 문장 정리의 참고 힌트이며 제공자·모델에 따라 적용 범위가 다릅니다.", "Register a spoken or recognized spelling and a preferred spelling as a pair. Each field is 1–100 characters. These are hints for speech recognition and text cleanup; support varies by provider and model."))
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(L("말하거나 인식된 표기", "Spoken or recognized spelling")); Spacer(); Text("\(spoken.count)/100").foregroundStyle(.secondary).monospacedDigit() }.font(AppTypography.caption)
                TextField(L("예: 오픈 노타입", "Example: open no type"), text: $spoken).textFieldStyle(.roundedBorder).focused($focusedField, equals: .spoken)
                    .onSubmit { focusedField = .written }.disabled(working || !editable)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(L("원하는 표기", "Preferred spelling")); Spacer(); Text("\(written.count)/100").foregroundStyle(.secondary).monospacedDigit() }.font(AppTypography.caption)
                TextField(L("예: OpenNoType", "Example: OpenNoType"), text: $written).textFieldStyle(.roundedBorder).focused($focusedField, equals: .written)
                    .onSubmit { save() }.disabled(working || !editable)
            }
            if spoken.count > 100 || written.count > 100 {
                Text(L("각 표기를 100자 이내로 줄여 주세요.", "Keep each spelling within 100 characters.")).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            HStack(spacing: 12) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("취소", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(draft.entry == nil ? L("사전에 등록", "Add to dictionary") : L("변경 저장", "Save changes"), action: save)
                    .buttonStyle(AppActionButtonStyle(primary: true)).keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .font(AppTypography.body).padding(24).frame(width: 480)
        .interactiveDismissDisabled(working)
        .onAppear { focusedField = draft.spoken.isEmpty ? .spoken : .written }
        .onChange(of: model.preferencesRecoveryRequired) { _, required in if required { dismiss() } }
        .onChange(of: model.dictionary.map(\.id)) { _, ids in if let entry = draft.entry, !ids.contains(entry.id) { dismiss() } }
    }
    private func save() {
        guard canSave else { return }
        working = true
        Task {
            let saved: Bool
            if let entry = draft.entry { saved = await model.updateDictionaryEntry(entry, spoken: spoken, written: written) }
            else { saved = await model.saveDictionaryEntry(spoken: spoken, written: written) }
            working = false
            if saved { dismiss() }
        }
    }
}

struct RecoveryView: View {
    @Bindable var model: AppModel
    @State private var lastRetriedID: UUID?
    @State private var deletingID: UUID?
    @State private var retryDrafts: [UUID: String] = [:]
    @State private var currentSettingsRetry: FailedRecording?

    @State private var selectedID: UUID?
    private var editable: Bool { !AppLaunch.isPreview && !model.preferencesRecoveryRequired && model.startupState == .ready }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let active = model.failures.filter { min($0.expiresAt, $0.createdAt.addingTimeInterval(86_400)) > context.date }.sorted { $0.createdAt > $1.createdAt }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("실패 녹음 \(active.count)개", "\(active.count) failed recordings")).font(AppTypography.caption).foregroundStyle(.secondary)
                    Spacer()
                    OptionHelp(title: L("같은 설정과 현재 설정", "Saved and current settings"), message: L("‘같은 설정’은 보관된 음성·문장 모델, 출력 언어와 말투를 사용합니다. 빠른 로컬 받아쓰기는 당시 로컬 모델로 인식하고 AI 문장 처리를 생략합니다. 번역 다듬기·Jev 검토·사전은 현재 설정을 사용하며 빠른 받아쓰기에는 자동 Jev 검토를 적용하지 않습니다. ‘현재 설정’으로 처리해도 원래 녹음의 만료 시각은 유지됩니다. 결과를 확인한 뒤 원하는 입력창에 직접 복사해 주세요.", "Saved settings use the stored speech and text models, output language and tone. Quick on-device dictation uses its stored local model and skips AI cleanup. Translation refinement, Jev and dictionary hints use current settings; quick dictation skips automatic Jev review. Current-settings recovery does not extend the recording's expiry. Review and copy the result into your text field."))
                }
                if active.isEmpty {
                    ScrollView { recoveryContents(nil, at: context.date) }
                } else {
                    HSplitView {
                        List(selection: $selectedID) {
                            ForEach(active) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.mode == .dictation && item.skippedTextProcessing == true ? L("바로 입력", "Direct input") : item.mode.title).font(AppTypography.body.weight(.medium))
                                    Text(item.createdAt, format: .dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale)).font(AppTypography.caption).foregroundStyle(.secondary)
                                    Text(expiryText(item, at: context.date)).font(AppTypography.caption).foregroundStyle(AppTheme.warm)
                                }.padding(.vertical, 6).tag(item.id)
                            }
                        }.listStyle(.plain).frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                            .accessibilityLabel(L("복구 녹음 목록", "Recovery recordings"))
                        ScrollView { recoveryContents(active.first { $0.id == selectedID }, at: context.date).padding(.leading, 12).padding(.trailing, 4) }
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onAppear { reconcileSelection(active) }
            .onChange(of: active.map(\.id)) { _, _ in reconcileSelection(active) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("현재 설정으로 다시 처리할까요?", "Retry with current settings?"), isPresented: Binding(get: { currentSettingsRetry != nil }, set: { if !$0 { currentSettingsRetry = nil } }), titleVisibility: .visible) {
            if let item = currentSettingsRetry {
                Button(L("현재 설정으로 다시 처리", "Retry with current settings")) { startRetry(item, useCurrentSettings: true); currentSettingsRetry = nil }
            }
            Button(L("취소", "Cancel"), role: .cancel) { currentSettingsRetry = nil }
        } message: { Text(currentSettingsRetryDescription) }
        .task {
            await model.refreshData()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await model.refreshData()
            }
        }
    }
    private func reconcileSelection(_ active: [FailedRecording]) {
        if !active.contains(where: { $0.id == selectedID }) { selectedID = active.first?.id }
        if let item = currentSettingsRetry, !active.contains(where: { $0.id == item.id }) { currentSettingsRetry = nil }
    }
    private func recoveryContents(_ item: FailedRecording?, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let composition = model.promptComposition {
                PromptCompositionResultView(composition: composition, isBusy: model.isBusy,
                    regenerationSettings: model.promptRegenerationSettings, onRegenerate: model.regeneratePrompt)
            }
            if model.isBusy, lastRetriedID != nil {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.status).font(AppTypography.body).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("처리 취소", "Cancel processing")) { model.cancel() }
                }
            }
            if let lastRetriedID, !model.isBusy, !model.failures.contains(where: { $0.id == lastRetriedID }), !model.result.isEmpty {
                Surface(L("다시 처리한 결과", "Reprocessed result")) {
                    Text(model.result).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                    Button(L("결과 복사", "Copy result"), systemImage: "doc.on.doc") { copyText(model.result, model: model) }
                        .buttonStyle(AppActionButtonStyle(primary: true))
                }
            }
            if let item { recoveryCard(item, at: date) }
            else if model.failures.isEmpty || !model.failures.contains(where: { min($0.expiresAt, $0.createdAt.addingTimeInterval(86_400)) > date }) {
                DataEmptyState(icon: "checkmark.circle", title: L("다시 처리할 녹음이 없어요", "No recordings to retry"), detail: L("처리에 실패해 보관한 녹음이 이곳에 표시됩니다.", "Saved failed recordings will appear here."))
            } else {
                DataEmptyState(icon: "waveform", title: L("녹음을 선택해 주세요", "Select a recording"), detail: L("남은 보관 시간과 처리 설정을 확인할 수 있어요.", "Check its expiry and processing settings."))
            }
        }.padding(.bottom, 12)
    }

    private func recoveryCard(_ item: FailedRecording, at date: Date) -> some View {
        let effectiveMode: InputMode = item.mode == .dictation && item.outputLanguage?.isTranslation == true ? .translation : item.mode
        let quick = effectiveMode == .dictation && item.skippedTextProcessing == true
        let local = quick || (item.usedLocalTranscription ?? (item.provider == .anthropic))
        let speech = local ? (item.localSpeechModel.flatMap(LocalSpeechModel.init(rawValue:)) ?? .largeV3).displayName : item.provider.displayName
        let text = quick ? L("AI 처리 없음", "No AI processing") : (item.textProvider ?? item.provider).displayName
        return Surface {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: modeIcon(effectiveMode)).font(.system(size: 23, weight: .light)).foregroundStyle(AppTheme.warm).frame(width: 30).padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(quick ? L("빠른 로컬 받아쓰기", "Quick on-device dictation")
                         : item.mode == .dictation && effectiveMode == .translation
                         ? L("받아쓰기 · 번역", "Dictation · Translation") : effectiveMode.title)
                        .font(AppTypography.body.weight(.medium))
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale)).font(AppTypography.caption).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        Text(L("음성: \(speech) · 문장: \(text)", "Speech: \(speech) · Text: \(text)"))
                        if effectiveMode == .translation {
                            Text("· \(item.mode == .dictation ? item.outputLanguage?.targetLanguage ?? item.targetLanguage : item.targetLanguage)")
                        }
                    }.font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(expiryText(item, at: date), systemImage: "hourglass")
                    .font(AppTypography.caption).foregroundStyle(AppTheme.warm)
            }
            if item.mode == .rewrite {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("수정할 원문 붙여넣기", "Paste the text to rewrite")).font(.system(size: 11, weight: .medium))
                    TextEditor(text: Binding(get: { retryDrafts[item.id] ?? "" }, set: { retryDrafts[item.id] = $0 }))
                        .font(AppTypography.caption).frame(minHeight: 88, maxHeight: 140).scrollContentBackground(.hidden)
                        .padding(8).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.08)))
                        .accessibilityLabel(L("다시 수정할 원문", "Text to rewrite again")).disabled(model.isBusy || !editable)
                    Text(L("원문은 저장하지 않아요. 다시 처리할 때 문장 처리 제공자에게 전송합니다.", "The original text is not saved. It is sent to the text provider when you retry."))
                        .font(AppTypography.caption).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
            HStack {
                Button(L("녹음 삭제", "Delete recording"), role: .destructive) {
                    guard editable, !model.isBusy, deletingID == nil else { return }
                    deletingID = item.id
                    if lastRetriedID == item.id { lastRetriedID = nil }
                    Task { await model.deleteFailure(item); retryDrafts.removeValue(forKey: item.id); deletingID = nil }
                }.disabled(model.isBusy || deletingID != nil || !editable)
                Spacer()
                Button(L("현재 설정으로 다시 처리…", "Retry with current settings…")) { currentSettingsRetry = item }
                    .disabled(!editable || model.isBusy || deletingID != nil || item.mode == .rewrite && (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L("같은 설정으로 다시 처리", "Retry with same settings"), systemImage: "arrow.clockwise") { startRetry(item, useCurrentSettings: false) }
                    .buttonStyle(AppActionButtonStyle(primary: true))
                    .disabled(!editable || model.isBusy || deletingID != nil || item.mode == .rewrite && (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var currentSettingsRetryDescription: String {
        let quick = model.preferences.usesFastDictation(for: currentSettingsRetry?.mode ?? .dictation)
        let needsLocal = model.preferences.needsLocal || quick
        let provider = model.preferences.provider.displayName
        let speech = needsLocal ? L("녹음 음성은 이 Mac에서 인식합니다.", "The recording is transcribed on this Mac.") : L("녹음 음성을 \(provider)으로 전송해 인식합니다.", "The recording is sent to \(provider) for transcription.")
        let filter = model.preferences.speakerFilterEnabled ? L("내 목소리 필터를 사용합니다.", "Your voice filter is enabled.") : L("내 목소리 필터를 사용하지 않습니다.", "Your voice filter is disabled.")
        let textProvider = model.preferences.effectiveTextProvider.displayName
        let routing = !quick && ((!needsLocal && model.preferences.provider == .openRouter) || model.preferences.effectiveTextProvider == .openRouter) ? L(" OpenRouter는 모델 공급자로 요청을 전달하며 실제 공급자는 달라질 수 있습니다.", " OpenRouter forwards requests to model providers, which may vary.") : ""
        let textData = currentSettingsRetry?.mode == .rewrite ? L("인식한 글과 수정할 원문", "the transcript and original text to rewrite") : L("인식한 글", "the transcript")
        let language: String
        if currentSettingsRetry?.mode == .translation {
            language = L(" 번역할 언어: \(model.preferences.targetLanguage).", " Target language: \(model.preferences.targetLanguage).")
        } else if currentSettingsRetry?.mode == .dictation {
            language = L(" 받아쓰기 출력 언어: \(model.preferences.dictationOutputLanguage.title).", " Dictation output language: \(model.preferences.dictationOutputLanguage.title).")
        } else { language = "" }
        let speechModel = needsLocal ? model.preferences.localSpeechModel.displayName : model.preferences.transcriptionModel
        if quick {
            return L("\(speech) 빠른 로컬 받아쓰기로 AI 문장 정리와 자동 Jev 검토를 생략합니다. 음성 인식 모델: \(speechModel). 음성과 인식 문장을 외부 AI로 보내지 않습니다.\(language) \(filter) 원래 녹음의 보관 만료 시각은 유지됩니다.", "\(speech) Quick on-device dictation skips AI text cleanup and automatic Jev review. Speech model: \(speechModel). Audio and transcripts are not sent to an external AI.\(language) \(filter) The original recording’s expiration time is unchanged.")
        }
        return L("\(speech) \(textData)은 \(textProvider)으로 전송합니다. 음성 인식 모델: \(speechModel), 문장 처리 모델: \(model.preferences.textModel).\(language) \(filter)\(routing) 원래 녹음의 보관 만료 시각은 유지됩니다.", "\(speech) Sends \(textData) to \(textProvider). Speech model: \(speechModel), text model: \(model.preferences.textModel).\(language) \(filter)\(routing) The original recording’s expiration time is unchanged.")
    }

    private func startRetry(_ item: FailedRecording, useCurrentSettings: Bool) {
        guard editable, !model.isBusy, deletingID == nil, model.failures.contains(where: { $0.id == item.id }), min(item.expiresAt, item.createdAt.addingTimeInterval(86_400)) > Date() else { return }
        if item.mode == .rewrite, (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        model.retrySelection = item.mode == .rewrite ? retryDrafts[item.id] ?? "" : ""
        lastRetriedID = item.id
        model.retry(item, useCurrentSettings: useCurrentSettings)
    }

    private func expiryText(_ item: FailedRecording, at date: Date) -> String {
        let seconds = max(0, min(item.expiresAt, item.createdAt.addingTimeInterval(86_400)).timeIntervalSince(date))
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 60 { return L("\(minutes / 60)시간 \(minutes % 60)분 후 삭제", "Deletes in \(minutes / 60)h \(minutes % 60)m") }
        if minutes > 0 { return L("\(minutes)분 후 삭제", "Deletes in \(minutes)m") }
        return L("곧 삭제", "Deletes soon")
    }
}

private struct DataPageHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AppTypography.pageTitle)
            OptionHelp(title: title, message: detail)
        }.padding(.top, 6)
    }
}

private struct DataSearchField: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel(L("검색 지우기", "Clear search"))
            }
        }.font(AppTypography.body).padding(.horizontal, 10).frame(minHeight: AppLayout.controlHeight)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DataEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 24, weight: .ultraLight)).foregroundStyle(AppTheme.accent.opacity(0.8))
            Text(title).font(AppTypography.sectionTitle)
            Text(detail).font(AppTypography.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

private struct DictionaryTransferDocument: Codable {
    let version: Int
    let entries: [DictionaryTransferEntry]
}

private struct DictionaryTransferEntry: Codable {
    let spoken: String
    let written: String
}

private enum DictionaryTransferError: LocalizedError {
    case tooLarge, unsupportedVersion, invalidEntries
    var errorDescription: String? {
        switch self {
        case .tooLarge: L("1 MB 이하의 JSON 파일을 선택해 주세요.", "Choose a JSON file no larger than 1 MB.")
        case .unsupportedVersion: L("이 사전 파일의 버전은 아직 지원하지 않습니다.", "This dictionary file version is not supported yet.")
        case .invalidEntries: L("각 표기가 1~100자인 사전 1~5,000개를 가져올 수 있습니다.", "Import 1–5,000 entries, with 1–100 characters per spelling.")
        }
    }
}

private func modeIcon(_ mode: InputMode) -> String {
    switch mode { case .dictation: "waveform"; case .translation: "character.bubble"; case .rewrite: "pencil.line"; case .prompt: "text.bubble" }
}

@MainActor private func copyText(_ text: String, model: AppModel, label: String? = nil) {
    let label = label ?? L("결과", "result")
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.setString(text, forType: .string) { model.notice = L("\(label) 복사 완료", "Copied \(label)") }
    else { model.error = L("복사하지 못했습니다. 텍스트를 선택해 직접 복사해 주세요.", "Could not copy the text. Select it and copy it manually.") }
}
