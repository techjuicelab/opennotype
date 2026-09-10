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
        DataPageHeading(title: "나의 말, 나의 기록", detail: model.preferences.historyEnabled ? (model.preferences.retentionDays == -1 ? "결과는 이 Mac에 암호화해 직접 삭제할 때까지 보관해요." : "결과는 이 Mac에 암호화해 \(model.preferences.retentionDays)일 동안 보관해요.") : "새로운 결과의 기록을 꺼 두었어요. 기존 기록은 보관 기간에 따라 삭제돼요.")
        HStack(spacing: 14) {
            DataSearchField(text: $search, prompt: "결과와 원문 검색")
            Text("\(matches.count)개").font(.system(size: 11)).foregroundStyle(.secondary)
            Button("전체 삭제", role: .destructive) { confirmsDeletion = true }
                .disabled(model.history.isEmpty || deleting)
        }
        if matches.isEmpty {
            DataEmptyState(icon: search.isEmpty ? "clock" : "magnifyingglass", title: search.isEmpty ? "아직 보관한 기록이 없어요" : "일치하는 기록이 없어요", detail: search.isEmpty ? "말을 글로 옮기면 이곳에서 다시 확인하고 복사할 수 있어요." : "다른 단어나 짧은 표현으로 검색해 보세요.")
        } else {
            LazyVStack(spacing: 14) {
                ForEach(matches) { entry in
                    Surface {
                        HStack(spacing: 9) {
                            Label(entry.mode.title, systemImage: modeIcon(entry.mode))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.accentForeground)
                            Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            Button { copyText(entry.resultText, model: model) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless).help("결과 복사").accessibilityLabel("결과 복사")
                            Button(role: .destructive) { delete(entry) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).disabled(deleting).help("이 기록 삭제").accessibilityLabel("이 기록 삭제")
                        }
                        Text(entry.resultText).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if entry.originalText != entry.resultText {
                            DisclosureGroup("처음 인식한 내용") {
                                Text(entry.originalText).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Text(entry.provider.displayName)
                            if let bundleID = entry.sourceBundleID { Text("·"); Text(bundleID).lineLimit(1).truncationMode(.middle) }
                        }.font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        Color.clear.frame(height: 0)
            .confirmationDialog("보관한 기록 \(model.history.count)개를 모두 삭제할까요?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("모든 기록 삭제", role: .destructive) { delete(nil) }
                Button("취소", role: .cancel) { }
            } message: { Text("이 Mac의 기록을 삭제합니다. 개인 사전과 아직 보관 중인 실패 녹음은 유지됩니다.") }
    }

    private func delete(_ entry: HistoryEntry?) {
        deleting = true
        Task { await model.deleteHistory(entry); deleting = false }
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
        DataPageHeading(title: "자주 쓰는 말을 더 정확하게", detail: "이름, 전문 용어, 원하는 표기를 알려 주세요. 음성 인식과 문장 정리에 함께 사용해요.")
        Surface("고친 표기 자동 학습") {
            Toggle("교정한 표기 자동 학습", isOn: $model.preferences.automaticLearningEnabled)
            Text("받아쓴 뒤 같은 입력창에서 고친 대소문자·일부 고유명사 철자처럼 범위가 좁고 명확한 교정만 기억합니다. 예: GR5Q → GROQ. 한글↔영문 표기와 일반 단어 변경은 직접 확인한 뒤 등록합니다.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text("입력 완료가 확인된 받아쓰기에서 30초 동안 확인하며, 수정한 표기가 약 3초 유지되면 학습합니다. 수치·버전·날짜·문장 전체의 변경은 자동 등록하지 않습니다. 입력이나 수정을 확인할 수 없는 앱에서는 아래에서 직접 등록해 주세요.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            Text("기록 저장과 별개인 설정입니다. 끄면 새 교정을 관찰하거나 자동 등록하지 않으며, 기존 사전은 유지합니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if model.canUndoLastLearning {
                Button("마지막 자동 학습 되돌리기", systemImage: "arrow.uturn.backward") { Task { await model.undoLastLearning() } }
                    .disabled(working)
            }
        }
        if let candidate = model.learningCandidate {
            Surface("확인할 교정이 있어요") {
                Text("자동으로 기억해도 되는 표기 교정인지 확인이 필요합니다. 반복해서 사용할 단어가 있다면 아래에서 직접 등록해 주세요.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 12) {
                    candidateText("입력한 내용", text: candidate.originalText)
                    candidateText("바꾼 내용", text: candidate.editedText)
                }
                HStack {
                    if let proposed = CorrectionLearner.proposedCorrection(original: candidate.originalText, edited: candidate.editedText) {
                        Button("표기 확인하고 등록", systemImage: "pencil") {
                            editing = nil; spoken = proposed.spoken; written = proposed.written; focusedField = .written
                        }
                    }
                    Button("단어 직접 등록", systemImage: "plus") { editing = nil; spoken = ""; written = ""; focusedField = .spoken }
                    Button("검토하지 않기") { Task { await model.dismissLearningCandidate() } }.foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        Surface(editing == nil ? "단어 등록" : "단어 수정") {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("말하거나 인식된 표기").font(.system(size: 11, weight: .medium))
                    TextField("예: 웨더", text: $spoken).textFieldStyle(.roundedBorder).focused($focusedField, equals: .spoken)
                        .onSubmit { focusedField = .written }
                }
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text("원하는 표기").font(.system(size: 11, weight: .medium))
                    TextField("예: weather", text: $written).textFieldStyle(.roundedBorder).focused($focusedField, equals: .written)
                        .onSubmit { if canSave { save() } }
                }
            }
            HStack(spacing: 10) {
                Text("각 항목은 100자 이내 · 음성 인식 참고 단어는 최대 24개, 문장 정리는 최대 200개를 최근 교정·관련성에 따라 선택합니다. 제공자와 모델에 따라 힌트 지원이 다릅니다.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if editing != nil { Button("취소") { resetEditor() }.disabled(working) }
                Button(editing == nil ? "사전에 등록" : "변경 저장", action: save).buttonStyle(.borderedProminent).disabled(!canSave)
            }
        }
        HStack(spacing: 12) {
            DataSearchField(text: $search, prompt: "단어와 표기 검색")
            Text("\(matches.count)개").font(.system(size: 11)).foregroundStyle(.secondary)
            Menu {
                Button("JSON 파일 가져오기…", systemImage: "square.and.arrow.down", action: importDictionary)
                Button("JSON 파일 내보내기…", systemImage: "square.and.arrow.up", action: exportDictionary).disabled(model.dictionary.isEmpty)
            } label: { Label("가져오기 · 내보내기", systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().disabled(working)
        }
        if matches.isEmpty {
            DataEmptyState(icon: "character.book.closed", title: search.isEmpty ? "나만의 표기를 알려 주세요" : "일치하는 단어가 없어요", detail: search.isEmpty ? "회사 이름, 자주 쓰는 영어 표현, 사람 이름부터 등록해 보세요." : "다른 표기로 검색하거나 새 단어를 등록해 보세요.")
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
            .confirmationDialog("사전 \(imported.count)개를 가져올까요?", isPresented: $confirmsImport, titleVisibility: .visible) {
                Button("사전 가져오기") { applyImport() }
                Button("취소", role: .cancel) { imported = [] }
            } message: {
                Text(replacementCount == 0 ? "기존 사전을 유지하면서 새 항목을 추가합니다." : "같은 인식 표기가 있는 \(replacementCount)개 항목은 가져온 표기로 바뀝니다. 나머지 사전은 유지됩니다.")
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
                if entry.learned { Label("교정에서 학습", systemImage: "sparkle").font(.system(size: 9)).foregroundStyle(AppTheme.accentForeground) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                editing = entry; spoken = entry.spoken; written = entry.written; focusedField = .written
            } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).disabled(working).help("단어 수정").accessibilityLabel("\(entry.written) 수정")
            Button(role: .destructive) {
                working = true
                Task { await model.deleteDictionaryEntry(entry); if editing?.id == entry.id { resetEditor() }; working = false }
            } label: { Image(systemName: "trash") }.buttonStyle(.borderless).disabled(working).help("단어 삭제").accessibilityLabel("\(entry.written) 삭제")
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
        panel.title = "개인 사전 내보내기"
        panel.nameFieldStringValue = "OpenNoType-사전.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message = "사전의 단어와 표기를 JSON 파일로 저장합니다. 내보낸 파일은 암호화되지 않습니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = DictionaryTransferDocument(version: 1, entries: model.dictionary.map { .init(spoken: $0.spoken, written: $0.written) })
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            model.notice = "사전 \(document.entries.count)개를 내보냈습니다."
        } catch { model.error = "사전을 내보내지 못했습니다. \(error.localizedDescription)" }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.title = "개인 사전 가져오기"
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
        } catch { model.error = "사전을 가져오지 못했습니다. \(error.localizedDescription)" }
    }

    private func applyImport() {
        working = true
        let entries = imported
        Task {
            if await model.importDictionary(entries) { model.notice = "사전 \(entries.count)개를 가져왔습니다." }
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
        DataPageHeading(title: "다시 이어서 처리하세요", detail: "처리하지 못한 녹음만 이 Mac에 암호화해 최대 24시간 보관해요. 처리에 성공하거나 시간이 지나면 삭제돼요.")
        if model.isBusy, lastRetriedID != nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("처리 취소") { model.cancel() }
            }.padding(.vertical, 4)
        }
        if let lastRetriedID, !model.isBusy, !model.failures.contains(where: { $0.id == lastRetriedID }), !model.result.isEmpty {
            Surface("다시 처리한 결과") {
                Text(model.result).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                Button("결과 복사", systemImage: "doc.on.doc") { copyText(model.result, model: model) }
            }
        }
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let active = model.failures.filter { min($0.expiresAt, $0.createdAt.addingTimeInterval(86_400)) > context.date }.sorted { $0.createdAt > $1.createdAt }
            if active.isEmpty {
                DataEmptyState(icon: "checkmark.circle", title: "다시 처리할 녹음이 없어요", detail: "처리에 실패한 녹음이 있으면 이곳에서 확인할 수 있어요.")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(active) { item in recoveryCard(item, at: context.date) }
                }
            }
        }
        Text("‘같은 설정’은 녹음 당시의 설정을 사용합니다. 모델 오류나 목소리 필터 문제는 설정을 바꾼 뒤 ‘현재 설정으로 복구’를 선택하세요. 결과를 확인한 뒤 원하는 입력창에 복사해 주세요.")
            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        Color.clear.frame(height: 0).confirmationDialog("현재 설정으로 다시 처리할까요?", isPresented: Binding(get: { currentSettingsRetry != nil }, set: { if !$0 { currentSettingsRetry = nil } }), titleVisibility: .visible) {
            if let item = currentSettingsRetry {
                Button("현재 설정으로 다시 처리") { startRetry(item, useCurrentSettings: true); currentSettingsRetry = nil }
            }
            Button("취소", role: .cancel) { currentSettingsRetry = nil }
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
        Surface {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: modeIcon(item.mode)).font(.system(size: 23, weight: .light)).foregroundStyle(AppTheme.warm).frame(width: 30).padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.mode.title).font(.system(size: 14, weight: .medium))
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        Text("처음 사용한 AI: \(item.provider.displayName)")
                        if item.mode == .translation { Text("· \(item.targetLanguage)") }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Label(expiryText(item, at: date), systemImage: "hourglass")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(AppTheme.warm)
            }
            if item.mode == .rewrite {
                VStack(alignment: .leading, spacing: 8) {
                    Text("수정할 원문 붙여넣기").font(.system(size: 11, weight: .medium))
                    TextEditor(text: Binding(get: { retryDrafts[item.id] ?? "" }, set: { retryDrafts[item.id] = $0 }))
                        .font(.system(size: 12)).frame(minHeight: 88, maxHeight: 140).scrollContentBackground(.hidden)
                        .padding(8).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.08)))
                        .accessibilityLabel("다시 수정할 원문").disabled(model.isBusy)
                    Text("원문은 저장하지 않아요. 다시 처리할 때 이 녹음의 AI 제공자에게 전송합니다.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
            HStack {
                Button("녹음 삭제", role: .destructive) {
                    deletingID = item.id
                    if lastRetriedID == item.id { lastRetriedID = nil }
                    Task { await model.deleteFailure(item); retryDrafts.removeValue(forKey: item.id); deletingID = nil }
                }.disabled(model.isBusy || deletingID != nil)
                Spacer()
                Button("현재 설정으로 복구") { currentSettingsRetry = item }
                    .disabled(model.isBusy || deletingID != nil || item.mode == .rewrite && (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("같은 설정으로 다시 처리", systemImage: "arrow.clockwise") { startRetry(item, useCurrentSettings: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || deletingID != nil || item.mode == .rewrite && (retryDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var currentSettingsRetryDescription: String {
        let provider = model.preferences.provider.displayName
        let speech = model.preferences.needsLocal ? "녹음 음성은 이 Mac에서 인식합니다." : "녹음 음성을 \(provider)으로 전송해 인식합니다."
        let filter = model.preferences.speakerFilterEnabled ? "내 목소리 필터를 사용합니다." : "내 목소리 필터를 사용하지 않습니다."
        let routing = model.preferences.provider == .openRouter ? " OpenRouter는 모델 공급자로 요청을 전달하며 실제 공급자는 달라질 수 있습니다." : ""
        let textData = currentSettingsRetry?.mode == .rewrite ? "인식한 글과 수정할 원문" : "인식한 글"
        let language = currentSettingsRetry?.mode == .translation ? " 번역할 언어: \(model.preferences.targetLanguage)." : ""
        return "\(speech) \(textData)은 \(provider)으로 전송합니다. 음성 인식 모델: \(model.preferences.needsLocal ? "로컬 Whisper" : model.preferences.transcriptionModel), 문장 처리 모델: \(model.preferences.textModel).\(language) \(filter)\(routing) 원래 녹음의 보관 만료 시각은 유지됩니다."
    }

    private func startRetry(_ item: FailedRecording, useCurrentSettings: Bool) {
        model.retrySelection = item.mode == .rewrite ? retryDrafts[item.id] ?? "" : ""
        lastRetriedID = item.id
        model.retry(item, useCurrentSettings: useCurrentSettings)
    }

    private func expiryText(_ item: FailedRecording, at date: Date) -> String {
        let seconds = max(0, min(item.expiresAt, item.createdAt.addingTimeInterval(86_400)).timeIntervalSince(date))
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 60 { return "\(minutes / 60)시간 \(minutes % 60)분 후 삭제" }
        if minutes > 0 { return "\(minutes)분 후 삭제" }
        return "곧 삭제"
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
                    .buttonStyle(.plain).accessibilityLabel("검색 지우기")
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
        case .tooLarge: "1 MB 이하의 JSON 파일을 선택해 주세요."
        case .unsupportedVersion: "이 사전 파일의 버전은 아직 지원하지 않습니다."
        case .invalidEntries: "각 표기가 1~100자인 사전 1~5,000개를 가져올 수 있습니다."
        }
    }
}

private func modeIcon(_ mode: InputMode) -> String {
    switch mode { case .dictation: "waveform"; case .translation: "character.bubble"; case .rewrite: "pencil.line" }
}

@MainActor private func copyText(_ text: String, model: AppModel) {
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.setString(text, forType: .string) { model.notice = "결과를 복사했습니다." }
    else { model.error = "결과를 복사하지 못했습니다. 텍스트를 선택해 직접 복사해 주세요." }
}
