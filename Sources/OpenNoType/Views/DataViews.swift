import AppKit
import OpenNoTypeCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var confirmsDeletion = false
    @State private var deleting = false

    private var matches: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.history.filter {
            query.isEmpty || $0.resultText.localizedCaseInsensitiveContains(query) || $0.originalText.localizedCaseInsensitiveContains(query)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        DataPageHeading(title: L("나의 말, 나의 기록", "Your words, your history"), detail: model.preferences.historyEnabled ? (model.preferences.retentionDays == -1 ? L("결과는 이 Mac에 암호화해 직접 삭제할 때까지 보관해요.", "Results are encrypted on this Mac and kept until you delete them.") : L("결과는 이 Mac에 암호화해 \(model.preferences.retentionDays)일 동안 보관해요.", "Results are encrypted on this Mac and kept for \(model.preferences.retentionDays) days.")) : L("새로운 결과의 기록을 꺼 두었어요. 기존 기록은 보관 기간에 따라 삭제돼요.", "Saving new results is off. Existing records are deleted according to your retention period."))
        HStack(spacing: 14) {
            DataSearchField(text: $search, prompt: L("결과와 원문 검색", "Search results and transcripts"))
            Text(L("\(matches.count)개", "\(matches.count) items")).font(.system(size: 11)).foregroundStyle(.secondary)
            Button(L("전체 삭제", "Delete all"), role: .destructive) { confirmsDeletion = true }
                .disabled(model.history.isEmpty || deleting)
        }
        if matches.isEmpty {
            DataEmptyState(icon: search.isEmpty ? "clock" : "magnifyingglass", title: search.isEmpty ? L("아직 보관한 기록이 없어요", "No saved records yet") : L("일치하는 기록이 없어요", "No matching records"), detail: search.isEmpty ? L("말을 글로 옮기면 이곳에서 다시 확인하고 복사할 수 있어요.", "Once you turn speech into text, you can review and copy it here.") : L("다른 단어나 짧은 표현으로 검색해 보세요.", "Try another word or a shorter search."))
        } else {
            LazyVStack(spacing: 14) {
                ForEach(matches) { entry in
                    HistoryEntryCard(model: model, entry: entry, deleting: deleting) { delete(entry) }
                }
            }
        }
        Color.clear.frame(height: 0)
            .confirmationDialog(L("보관한 기록 \(model.history.count)개를 모두 삭제할까요?", "Delete all \(model.history.count) saved records?"), isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button(L("모든 기록 삭제", "Delete all records"), role: .destructive) { delete(nil) }
                Button(L("취소", "Cancel"), role: .cancel) { }
            } message: { Text(L("이 Mac의 기록과 학습한 Jev 오류 유형을 삭제하고, 진행 중인 검토와 진단도 지웁니다. 개인 사전과 아직 보관 중인 실패 녹음은 유지됩니다.", "Deletes history and learned Jev error categories on this Mac, and clears pending reviews and diagnostics. Your dictionary and saved failed recordings are kept.")) }
    }

    private func delete(_ entry: HistoryEntry?) {
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

    var body: some View {
        Surface {
            HStack(spacing: 9) {
                Label(entry.mode == .dictation && entry.effectiveMode == .translation
                      ? L("받아쓰기 · 번역", "Dictation · Translation") : entry.effectiveMode.title,
                      systemImage: modeIcon(entry.effectiveMode))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.accentForeground)
                Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().locale(AppLocalization.shared.language.locale))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).disabled(deleting).help(L("이 기록 삭제", "Delete this record")).accessibilityLabel(L("이 기록 삭제", "Delete this record"))
            }
            if let translationLanguage {
                Text(L("당시 출력 언어: \(translationLanguage)", "Captured output language: \(translationLanguage)"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            textBlock(L("보관된 결과", "Saved result"), text: entry.resultText, copyLabel: L("결과 복사", "Copy result"))
            DisclosureGroup(entry.mode == .rewrite ? L("음성 수정 지시 확인", "View spoken rewrite instructions") : L("인식 원문과 비교", "Compare with transcript")) {
                VStack(alignment: .leading, spacing: 8) {
                    textBlock(originalTitle, text: entry.originalText, copyLabel: L("\(originalTitle) 복사", "Copy \(originalTitle)"))
                    if entry.originalText == entry.resultText {
                        Text(L("인식 원문과 보관된 결과가 같아요.", "The transcript and saved result are identical.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
            }.font(.system(size: 12))
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
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            if let reason = model.historyReprocessingUnavailableReason(for: entry) {
                Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                DisclosureGroup(L("현재 설정으로 다시 처리", "Retry with current settings")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.historyReprocessingSettings(for: entry))
                            .font(.system(size: 11, weight: .medium)).textSelection(.enabled)
                        Text(L("인식 원문을 현재 제공자에 보내 문장만 다시 처리해요. 기존 결과는 그대로 보관하며, 새 결과를 확인하고 복사할 수 있어요. API 사용 비용이 발생할 수 있어요.", "Sends the transcript to your current provider for text processing. The saved result stays unchanged, and you can review and copy the new result. API charges may apply."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        if entry.mode == .translation && translationLanguage == nil {
                            Text(L("당시 번역 언어가 없거나 확인할 수 없어 위에 표시된 현재 번역 언어를 사용해요.", "The captured translation language is missing or invalid, so the current language shown above is used."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else if entry.effectiveMode == .translation {
                            Text(L("위에 표시된 현재 출력 언어로 다시 처리합니다. 당시 번역 언어와 다를 수 있습니다.", "Reprocesses in the current output language shown above, which may differ from the captured translation language."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(L("프로필은 이 기록의 앱에 지정된 현재 설정을 사용해요. 당시 입력창의 주변 문맥은 저장되어 있지 않아요.", "Uses the current profile assigned to this record’s app. The text field’s surrounding context was not saved."))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Button(L("원문 다시 처리", "Reprocess transcript"), systemImage: "arrow.clockwise") { model.reprocessHistory(entry) }
                            .disabled(model.isBusy || deleting)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
            if let preview = model.historyReprocessing, preview.entryID == entry.id {
                Divider()
                HStack {
                    Label(L("다시 처리한 결과 · 미리보기", "Reprocessed result · Preview"), systemImage: "text.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(preview.isProcessing ? L("취소", "Cancel") : L("미리보기 닫기", "Close preview")) { model.dismissHistoryReprocessing() }
                        .buttonStyle(.borderless)
                }
                Text(preview.settingsDescription).font(.system(size: 10)).foregroundStyle(.secondary)
                if preview.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("문장을 다시 처리하고 있어요…", "Reprocessing text…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else if let result = preview.result {
                    textBlock(preview.translationRefinement?.held == true ? L("번역 초안", "Draft translation") : L("새 결과", "New result"),
                              text: result, copyLabel: preview.translationRefinement?.held == true ? L("초안 복사", "Copy draft") : L("새 결과 복사", "Copy new result"))
                    if let error = preview.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(AppTheme.warm).textSelection(.enabled)
                    }
                    Text(L("미리보기는 별도로 보관하지 않아요. 필요한 결과를 복사해 주세요.", "This preview is not saved separately. Copy the result if you need it."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
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
                    Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
                }
                if let refinement = preview.translationRefinement {
                    TranslationRefinementResultView(refinement: refinement)
                }
            }
            HStack(spacing: 8) {
                Text(entry.provider.displayName)
                if let bundleID = entry.sourceBundleID { Text("·"); Text(bundleID).lineLimit(1).truncationMode(.middle) }
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func textBlock(_ title: String, text: String, copyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(copyLabel, systemImage: "doc.on.doc") { copyText(text, model: model, label: title) }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
            Text(text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DictionaryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var spoken = ""
    @State private var written = ""
    @State private var editing: DictionaryEntry?
    @State private var working = false
    @State private var imported: [DictionaryEntry] = []
    @State private var confirmsImport = false
    @FocusState private var focusedField: DictionaryField?
    private enum DictionaryField { case spoken, written }

    private var matches: [DictionaryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.dictionary.filter { query.isEmpty || $0.spoken.localizedCaseInsensitiveContains(query) || $0.written.localizedCaseInsensitiveContains(query) }
            .sorted { $0.written.localizedStandardCompare($1.written) == .orderedAscending }
    }
    private var canSave: Bool {
        !working && !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && spoken.count <= 100 && written.count <= 100
    }
    private var replacementCount: Int {
        imported.filter { item in model.dictionary.contains { $0.spoken.caseInsensitiveCompare(item.spoken) == .orderedSame } }.count
    }

    var body: some View {
        DataPageHeading(title: L("자주 쓰는 말을 더 정확하게", "Get your usual words right"), detail: L("이름, 전문 용어, 원하는 표기를 알려 주세요. 음성 인식과 문장 정리에 함께 사용해요.", "Add names, technical terms and preferred spellings. They help both speech recognition and text cleanup."))
        JevNameCatalogView(model: model)
        if model.decisionProposalStatus != nil || model.canUndoDecisionDictionarySave {
            Surface(L("Jev 제안에서 저장한 표기", "Spellings saved from Jev suggestions")) {
                JevDictionaryUndoView(model: model)
            }
        }
        Surface(L("고친 표기 자동 학습", "Learn corrected spellings")) {
            Toggle(L("교정한 표기 자동 학습", "Automatically learn corrected spellings"), isOn: $model.preferences.automaticLearningEnabled)
            Text(L("받아쓴 뒤 같은 입력창에서 고친 대소문자·일부 고유명사 철자처럼 범위가 좁고 명확한 교정만 기억합니다. 예: GR5Q → GROQ. 한글↔영문 표기와 일반 단어 변경은 직접 확인한 뒤 등록합니다.", "Learns only narrow, clear corrections made in the same text field after dictation, such as capitalization and some proper-name spellings. Example: GR5Q → GROQ. Review and register Korean–English spellings and ordinary word changes yourself."))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text(L("입력 완료가 확인된 받아쓰기에서 30초 동안 확인하며, 수정한 표기가 약 3초 유지되면 학습합니다. 수치·버전·날짜·문장 전체의 변경은 자동 등록하지 않습니다. 입력이나 수정을 확인할 수 없는 앱에서는 아래에서 직접 등록해 주세요.", "Watches confirmed dictation for 30 seconds and learns a correction after it stays for about 3 seconds. Changes to numbers, versions, dates or entire sentences are not registered automatically. Add entries below when an app’s input or edits cannot be verified."))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            Text(L("기록 저장과 별개인 설정입니다. 끄면 새 교정을 관찰하거나 자동 등록하지 않으며, 기존 사전은 유지합니다.", "This setting is separate from history. Turning it off stops observing and learning new corrections; existing dictionary entries are kept."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if model.canUndoLastLearning {
                Button(L("마지막 자동 학습 되돌리기", "Undo last learned spelling"), systemImage: "arrow.uturn.backward") { Task { await model.undoLastLearning() } }
                    .disabled(working)
            }
        }
        if let candidate = model.learningCandidate {
            Surface(L("확인할 교정이 있어요", "A correction needs review")) {
                Text(L("자동으로 기억해도 되는 표기 교정인지 확인이 필요합니다. 반복해서 사용할 단어가 있다면 아래에서 직접 등록해 주세요.", "Review whether this is a spelling correction worth learning. Add any terms you want to use again below."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 12) {
                    candidateText(L("입력한 내용", "Original text"), text: candidate.originalText)
                    candidateText(L("바꾼 내용", "Edited text"), text: candidate.editedText)
                }
                JevCorrectionReviewView(model: model, candidate: candidate)
                HStack {
                    if let proposed = CorrectionLearner.reviewProposal(original: candidate.originalText, edited: candidate.editedText) {
                        Button(L("표기 확인하고 등록", "Review and register spelling"), systemImage: "pencil") {
                            editing = nil; spoken = proposed.spoken; written = proposed.written; focusedField = .written
                        }
                    }
                    Button(L("단어 직접 등록", "Add a word"), systemImage: "plus") { editing = nil; spoken = ""; written = ""; focusedField = .spoken }
                    Button(L("검토하지 않기", "Dismiss review")) { Task { await model.dismissLearningCandidate() } }.foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        Surface(editing == nil ? L("단어 등록", "Add a word") : L("단어 수정", "Edit word")) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("말하거나 인식된 표기", "Spoken or recognized spelling")).font(.system(size: 11, weight: .medium))
                    TextField(L("예: 웨더", "Example: open router"), text: $spoken).textFieldStyle(.roundedBorder).focused($focusedField, equals: .spoken)
                        .onSubmit { focusedField = .written }
                }
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("원하는 표기", "Preferred spelling")).font(.system(size: 11, weight: .medium))
                    TextField(L("예: weather", "Example: OpenRouter"), text: $written).textFieldStyle(.roundedBorder).focused($focusedField, equals: .written)
                        .onSubmit { if canSave { save() } }
                }
            }
            HStack(spacing: 10) {
                Text(L("각 항목은 100자 이내 · 음성 인식 참고 단어는 최대 24개, 문장 정리는 최대 200개를 최근 교정·관련성에 따라 선택합니다. 제공자와 모델에 따라 힌트 지원이 다릅니다.", "Up to 100 characters per field. Speech recognition selects up to 24 terms and text cleanup up to 200, based on recent corrections and relevance. Hint support varies by provider and model.")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if editing != nil { Button(L("취소", "Cancel")) { resetEditor() }.disabled(working) }
                Button(editing == nil ? L("사전에 등록", "Add to dictionary") : L("변경 저장", "Save changes"), action: save).buttonStyle(.borderedProminent).disabled(!canSave)
            }
        }
        HStack(spacing: 12) {
            DataSearchField(text: $search, prompt: L("단어와 표기 검색", "Search words and spellings"))
            Text(L("\(matches.count)개", "\(matches.count) items")).font(.system(size: 11)).foregroundStyle(.secondary)
            Menu {
                Button(L("JSON 파일 가져오기…", "Import JSON file…"), systemImage: "square.and.arrow.down", action: importDictionary)
                Button(L("JSON 파일 내보내기…", "Export JSON file…"), systemImage: "square.and.arrow.up", action: exportDictionary).disabled(model.dictionary.isEmpty)
            } label: { Label(L("가져오기 · 내보내기", "Import & Export"), systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().disabled(working)
        }
        if matches.isEmpty {
            DataEmptyState(icon: "character.book.closed", title: search.isEmpty ? L("나만의 표기를 알려 주세요", "Add your preferred spellings") : L("일치하는 단어가 없어요", "No matching words"), detail: search.isEmpty ? L("회사 이름, 자주 쓰는 영어 표현, 사람 이름부터 등록해 보세요.", "Start with company names, common English terms or people’s names.") : L("다른 표기로 검색하거나 새 단어를 등록해 보세요.", "Search another spelling or add a new word."))
        } else {
            Surface {
                LazyVStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.vertical, 13) }
                        dictionaryRow(entry)
                    }
                }
            }
        }
        Color.clear.frame(height: 0)
            .confirmationDialog(L("사전 \(imported.count)개를 가져올까요?", "Import \(imported.count) dictionary entries?"), isPresented: $confirmsImport, titleVisibility: .visible) {
                Button(L("사전 가져오기", "Import dictionary")) { applyImport() }
                Button(L("취소", "Cancel"), role: .cancel) { imported = [] }
            } message: {
                Text(replacementCount == 0 ? L("기존 사전을 유지하면서 새 항목을 추가합니다.", "Adds new entries while keeping your existing dictionary.") : L("같은 인식 표기가 있는 \(replacementCount)개 항목은 가져온 표기로 바뀝니다. 나머지 사전은 유지됩니다.", "Replaces \(replacementCount) entries with matching recognized spellings. All other entries are kept."))
            }
    }

    private func candidateText(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dictionaryRow(_ entry: DictionaryEntry) -> some View {
        HStack(alignment: .center, spacing: 15) {
            Text(entry.spoken).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.written).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                if entry.learned { Label(L("교정에서 학습", "Learned from a correction"), systemImage: "sparkle").font(.system(size: 9)).foregroundStyle(AppTheme.accentForeground) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                editing = entry; spoken = entry.spoken; written = entry.written; focusedField = .written
            } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).disabled(working).help(L("단어 수정", "Edit word")).accessibilityLabel(L("\(entry.written) 수정", "Edit \(entry.written)"))
            Button(role: .destructive) {
                working = true
                Task { await model.deleteDictionaryEntry(entry); if editing?.id == entry.id { resetEditor() }; working = false }
            } label: { Image(systemName: "trash") }.buttonStyle(.borderless).disabled(working).help(L("단어 삭제", "Delete word")).accessibilityLabel(L("\(entry.written) 삭제", "Delete \(entry.written)"))
        }
    }

    private func save() {
        guard canSave else { return }
        working = true
        Task {
            if let editing {
                if await model.updateDictionaryEntry(editing, spoken: spoken, written: written) { resetEditor() }
            } else {
                if await model.saveDictionaryEntry(spoken: spoken, written: written) { resetEditor() }
            }
            working = false
        }
    }

    private func resetEditor() { editing = nil; spoken = ""; written = ""; focusedField = nil }

    private func exportDictionary() {
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
        working = true
        let entries = imported
        Task {
            if await model.importDictionary(entries) { model.notice = L("사전 \(entries.count)개를 가져왔습니다.", "Imported \(entries.count) dictionary entries.") }
            imported = []; working = false
        }
    }
}

struct RecoveryView: View {
    @Bindable var model: AppModel
    @State private var lastRetriedID: UUID?
    @State private var deletingID: UUID?
    @State private var retryDrafts: [UUID: String] = [:]
    @State private var currentSettingsRetry: FailedRecording?

    var body: some View {
        DataPageHeading(title: L("다시 이어서 처리하세요", "Pick up where you left off"), detail: L("처리하지 못한 녹음만 이 Mac에 암호화해 최대 24시간 보관해요. 처리에 성공하거나 시간이 지나면 삭제돼요.", "Failed recordings are encrypted on this Mac for up to 24 hours. They are deleted after successful processing or when they expire."))
        if model.isBusy, lastRetriedID != nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(L("처리 취소", "Cancel processing")) { model.cancel() }
            }.padding(.vertical, 4)
        }
        if let lastRetriedID, !model.isBusy, !model.failures.contains(where: { $0.id == lastRetriedID }), !model.result.isEmpty {
            Surface(L("다시 처리한 결과", "Reprocessed result")) {
                Text(model.result).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button(L("결과 복사", "Copy result"), systemImage: "doc.on.doc") { copyText(model.result, model: model) }
            }
        }
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let active = model.failures.filter { min($0.expiresAt, $0.createdAt.addingTimeInterval(86_400)) > context.date }.sorted { $0.createdAt > $1.createdAt }
            if active.isEmpty {
                DataEmptyState(icon: "checkmark.circle", title: L("다시 처리할 녹음이 없어요", "No recordings to retry"), detail: L("처리에 실패한 녹음이 있으면 이곳에서 확인할 수 있어요.", "Recordings that fail to process will appear here."))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(active) { item in recoveryCard(item, at: context.date) }
                }
            }
        }
        Text(L("‘같은 설정’은 보관된 음성·문장 모델, 출력 언어와 말투를 사용합니다. 번역 다듬기·Jev 검토·사전은 현재 설정을 사용합니다. 모델 오류나 목소리 필터 문제는 설정을 바꾼 뒤 ‘현재 설정으로 복구’를 선택하세요. 결과를 확인한 뒤 원하는 입력창에 복사해 주세요.", "“Same settings” uses the saved speech and text models, output language and tone. Translation refinement, Jev review and dictionary hints use your current settings. For model errors or voice-filter issues, change your settings and choose “Recover with current settings.” Review the result and copy it into your text field."))
            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        Color.clear.frame(height: 0).confirmationDialog(L("현재 설정으로 다시 처리할까요?", "Retry with current settings?"), isPresented: Binding(get: { currentSettingsRetry != nil }, set: { if !$0 { currentSettingsRetry = nil } }), titleVisibility: .visible) {
            if let item = currentSettingsRetry {
                Button(L("현재 설정으로 다시 처리", "Retry with current settings")) { startRetry(item, useCurrentSettings: true); currentSettingsRetry = nil }
            }
            Button(L("취소", "Cancel"), role: .cancel) { currentSettingsRetry = nil }
        } message: {
            Text(currentSettingsRetryDescription)
        }
        Color.clear.frame(height: 0).task {
            await model.refreshData()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await model.refreshData()
            }
        }
    }

    private func recoveryCard(_ item: FailedRecording, at date: Date) -> some View {
        let effectiveMode: InputMode = item.mode == .dictation && item.outputLanguage?.isTranslation == true ? .translation : item.mode
        return Surface {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: modeIcon(effectiveMode)).font(.system(size: 23, weight: .light)).foregroundStyle(AppTheme.warm).frame(width: 30).padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.mode == .dictation && effectiveMode == .translation
                         ? L("받아쓰기 · 번역", "Dictation · Translation") : effectiveMode.title)
                        .font(.system(size: 14, weight: .medium))
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute().locale(AppLocalization.shared.language.locale)).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        Text(L("음성: \((item.usedLocalTranscription ?? (item.provider == .anthropic)) ? "이 Mac" : item.provider.displayName) · 문장: \((item.textProvider ?? item.provider).displayName)", "Speech: \((item.usedLocalTranscription ?? (item.provider == .anthropic)) ? L("이 Mac", "This Mac") : item.provider.displayName) · Text: \((item.textProvider ?? item.provider).displayName)"))
                        if effectiveMode == .translation {
                            Text("· \(item.mode == .dictation ? item.outputLanguage?.targetLanguage ?? item.targetLanguage : item.targetLanguage)")
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Label(expiryText(item, at: date), systemImage: "hourglass")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(AppTheme.warm)
            }
            if item.mode == .rewrite {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("수정할 원문 붙여넣기", "Paste the text to rewrite")).font(.system(size: 11, weight: .medium))
                    TextEditor(text: Binding(get: { retryDrafts[item.id] ?? "" }, set: { retryDrafts[item.id] = $0 }))
                        .font(.system(size: 12)).frame(minHeight: 88, maxHeight: 140).scrollContentBackground(.hidden)
                        .padding(8).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.08)))
                        .accessibilityLabel(L("다시 수정할 원문", "Text to rewrite again")).disabled(model.isBusy)
                    Text(L("원문은 저장하지 않아요. 다시 처리할 때 문장 처리 제공자에게 전송합니다.", "The original text is not saved. It is sent to the text provider when you retry."))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
            HStack {
                Button(L("녹음 삭제", "Delete recording"), role: .destructive) {
                    deletingID = item.id
                    if lastRetriedID == item.id { lastRetriedID = nil }
                    Task { await model.deleteFailure(item); retryDrafts.removeValue(forKey: item.id); deletingID = nil }
                }.disabled(model.isBusy || deletingID != nil)
                Spacer()
                Button(L("현재 설정으로 복구", "Recover with current settings")) { currentSettingsRetry = item }
                    .disabled(model.isBusy || deletingID != nil || item.mode == .rewrite && (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L("같은 설정으로 다시 처리", "Retry with same settings"), systemImage: "arrow.clockwise") { startRetry(item, useCurrentSettings: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || deletingID != nil || item.mode == .rewrite && (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var currentSettingsRetryDescription: String {
        let provider = model.preferences.provider.displayName
        let speech = model.preferences.needsLocal ? L("녹음 음성은 이 Mac에서 인식합니다.", "The recording is transcribed on this Mac.") : L("녹음 음성을 \(provider)으로 전송해 인식합니다.", "The recording is sent to \(provider) for transcription.")
        let filter = model.preferences.speakerFilterEnabled ? L("내 목소리 필터를 사용합니다.", "Your voice filter is enabled.") : L("내 목소리 필터를 사용하지 않습니다.", "Your voice filter is disabled.")
        let textProvider = model.preferences.effectiveTextProvider.displayName
        let routing = model.preferences.provider == .openRouter || model.preferences.effectiveTextProvider == .openRouter ? L(" OpenRouter는 모델 공급자로 요청을 전달하며 실제 공급자는 달라질 수 있습니다.", " OpenRouter forwards requests to model providers, which may vary.") : ""
        let textData = currentSettingsRetry?.mode == .rewrite ? L("인식한 글과 수정할 원문", "the transcript and original text to rewrite") : L("인식한 글", "the transcript")
        let language: String
        if currentSettingsRetry?.mode == .translation {
            language = L(" 번역할 언어: \(model.preferences.targetLanguage).", " Target language: \(model.preferences.targetLanguage).")
        } else if currentSettingsRetry?.mode == .dictation {
            language = L(" 받아쓰기 출력 언어: \(model.preferences.dictationOutputLanguage.title).", " Dictation output language: \(model.preferences.dictationOutputLanguage.title).")
        } else { language = "" }
        let speechModel = model.preferences.needsLocal ? L("로컬 Whisper", "Local Whisper") : model.preferences.transcriptionModel
        return L("\(speech) \(textData)은 \(textProvider)으로 전송합니다. 음성 인식 모델: \(speechModel), 문장 처리 모델: \(model.preferences.textModel).\(language) \(filter)\(routing) 원래 녹음의 보관 만료 시각은 유지됩니다.", "\(speech) Sends \(textData) to \(textProvider). Speech model: \(speechModel), text model: \(model.preferences.textModel).\(language) \(filter)\(routing) The original recording’s expiration time is unchanged.")
    }

    private func startRetry(_ item: FailedRecording, useCurrentSettings: Bool) {
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
            Text(title).font(.system(size: 25, weight: .semibold)).tracking(-0.7)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
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
        }.font(.system(size: 12)).padding(.horizontal, 11).padding(.vertical, 9)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DataEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 32, weight: .ultraLight)).foregroundStyle(AppTheme.accent.opacity(0.8))
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 50)
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
    switch mode { case .dictation: "waveform"; case .translation: "character.bubble"; case .rewrite: "pencil.line" }
}

@MainActor private func copyText(_ text: String, model: AppModel, label: String? = nil) {
    let label = label ?? L("결과", "result")
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.setString(text, forType: .string) { model.notice = L("\(label) 복사 완료", "Copied \(label)") }
    else { model.error = L("복사하지 못했습니다. 텍스트를 선택해 직접 복사해 주세요.", "Could not copy the text. Select it and copy it manually.") }
}
