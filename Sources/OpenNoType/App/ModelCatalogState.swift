import Foundation
import OpenNoTypeCore

/// Models found by explicit searches and compatibility test results. Stored separately from
/// preferences so that a large or unreadable list can never put settings into recovery.
struct ModelCatalogSnapshot: Codable, Equatable {
    var models: [DiscoveredModel] = []
    var results: [String: ModelCompatibilityResult] = [:]
    var lastSearchAt: Date?
    var searchedProviders: Set<AIProvider> = []

    private static let key = "modelCatalog.v1"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    var newCount: Int { models.filter(\.isNew).count }

    func models(for provider: AIProvider, kind: DiscoveredModel.Kind) -> [DiscoveredModel] {
        models.filter { $0.provider == provider && $0.kind == kind }
    }
}

/// The text task a compatibility test exercises, including the two additional roles.
enum CompatibilityTask: String {
    case cleanup, translation, rewrite, prompt, refinement, alternative

    init(_ task: TextTask) {
        switch task {
        case .translation: self = .translation
        case .rewrite: self = .rewrite
        case .prompt: self = .prompt
        case .refinement: self = .refinement
        }
    }

    var usageMode: InputMode {
        switch self {
        case .cleanup, .alternative: .dictation
        case .translation, .refinement: .translation
        case .rewrite: .rewrite
        case .prompt: .prompt
        }
    }

    /// Fixed synthetic input; no recording, history or personal text is sent.
    func request() -> ProcessingRequest {
        switch self {
        case .cleanup, .alternative:
            return ProcessingRequest(mode: .dictation, transcript: L("음 내일 오후 세 시에 그 회의 시작해 주세요", "um please start the meeting tomorrow at three pm"), dictionary: [])
        case .translation, .refinement:
            return ProcessingRequest(mode: .translation, transcript: "내일 오후 세 시에 회의를 시작해 주세요.", dictionary: [], targetLanguage: "English (United States)")
        case .rewrite:
            return ProcessingRequest(mode: .rewrite, transcript: L("더 공손하게 바꿔 줘", "make it more polite"), selectedText: L("회의는 3시에 시작해.", "Start the meeting at 3."), dictionary: [])
        case .prompt:
            return ProcessingRequest(mode: .prompt, transcript: L("회의록을 요약하는 체크리스트를 만들어 달라고 요청해 줘", "ask for a checklist that summarizes meeting notes"), dictionary: [])
        }
    }
}

extension AppModel {
    func compatibilityResult(provider: AIProvider, model: String, task: CompatibilityTask) -> ModelCompatibilityResult? {
        modelCatalog.results[ModelCompatibilityResult.key(provider: provider, modelID: model, task: task.rawValue)]
    }

    func isTestingCompatibility(provider: AIProvider, model: String, task: CompatibilityTask) -> Bool {
        compatibilityTestsInProgress.contains(ModelCompatibilityResult.key(provider: provider, modelID: model, task: task.rawValue))
    }

    /// Sends one short synthetic request through the same path real processing uses. It never
    /// records audio, types text or writes history; usage is recorded when usage records are on.
    func testCompatibility(provider: AIProvider, model: String, task: CompatibilityTask) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ModelCompatibilityResult.key(provider: provider, modelID: trimmed, task: task.rawValue)
        guard !AppLaunch.isPreview, startupState == .ready, !trimmed.isEmpty, !compatibilityTestsInProgress.contains(key) else { return }
        let selected = preferences, usageEpoch = currentUsageEpoch, job = UUID()
        compatibilityTestsInProgress.insert(key)
        Task { [weak self] in
            guard let self else { return }
            defer { compatibilityTestsInProgress.remove(key) }
            let costs = UsageCollector()
            let started = ProcessInfo.processInfo.systemUptime
            var result: ModelCompatibilityResult
            do {
                try await prepareStoredKeys(for: [provider])
                var config = try configuration(provider: provider, preferences: selected)
                config.textModel = trimmed
                let mode = task.usageMode
                _ = try await processForCompatibility(task.request(), configuration: config) { [weak self] event in
                    await costs.add(event)
                    await self?.recordCompatibilityUsage(event, job: job, mode: mode, epoch: usageEpoch, tracking: selected.usageTrackingEnabled)
                }
                let collected = await costs.snapshot()
                result = ModelCompatibilityResult(provider: provider, modelID: trimmed, task: task.rawValue, passed: true,
                                                  latencySeconds: ProcessInfo.processInfo.systemUptime - started,
                                                  reportedModel: collected.reportedModel, costUSD: collected.costUSD)
            } catch is CancellationError {
                return
            } catch {
                let collected = await costs.snapshot()
                result = ModelCompatibilityResult(provider: provider, modelID: trimmed, task: task.rawValue, passed: false,
                                                  latencySeconds: ProcessInfo.processInfo.systemUptime - started,
                                                  reportedModel: collected.reportedModel, costUSD: collected.costUSD,
                                                  failure: error.localizedDescription)
            }
            modelCatalog.results[key] = result
            modelCatalog.save()
        }
    }

    /// Lists models from OpenRouter's public catalog and from providers whose key is already
    /// loaded. Nothing is selected or changed; newly appearing models are only marked.
    func searchModels() {
        guard !AppLaunch.isPreview, !modelSearchInProgress else { return }
        modelSearchInProgress = true
        modelSearchSummary = nil
        let firstSearch = modelCatalog.lastSearchAt == nil
        let providers = AIProvider.allCases
        let keys = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in loadedKey(provider).map { (provider, $0) } })
        Task { [weak self] in
            guard let self else { return }
            defer { modelSearchInProgress = false }
            var catalog = modelCatalog
            var failures: [String] = [], skipped: [String] = []
            for provider in providers {
                guard provider == .openRouter || keys[provider] != nil else { skipped.append(provider.displayName); continue }
                do {
                    let fetched = try await ModelDiscovery.fetch(provider, apiKey: keys[provider])
                    let catalogIDs = Set(TextModelCatalog.entries(for: provider).map(\.id) + SpeechModelCatalog.entries(for: provider).map(\.id))
                    catalog.models = ModelDiscovery.merge(previous: catalog.models, fetched: fetched, provider: provider,
                                                          catalogIDs: catalogIDs, isFirstSearch: firstSearch || !catalog.searchedProviders.contains(provider))
                    catalog.searchedProviders.insert(provider)
                } catch is CancellationError {
                    return
                } catch ModelDiscovery.Failure.http(let status) {
                    failures.append(status == 401 || status == 403
                                    ? L("\(provider.displayName): 키 확인 필요", "\(provider.displayName): check key")
                                    : "\(provider.displayName): HTTP \(status)")
                } catch {
                    failures.append(L("\(provider.displayName): 연결 실패", "\(provider.displayName): connection failed"))
                }
            }
            catalog.lastSearchAt = Date()
            modelCatalog = catalog
            modelCatalog.save()
            var parts: [String] = []
            parts.append(firstSearch
                         ? L("모델 \(catalog.models.count)개를 불러왔습니다. 다음 검색부터 새로 나온 모델을 표시합니다.", "Loaded \(catalog.models.count) models. Newly released models are marked from the next search.")
                         : catalog.newCount > 0 ? L("새 후보 \(catalog.newCount)개", "\(catalog.newCount) new candidates") : L("새 모델 없음", "No new models"))
            if !failures.isEmpty { parts.append(failures.joined(separator: ", ")) }
            if !skipped.isEmpty { parts.append(L("키 확인 전이라 건너뜀: \(skipped.joined(separator: ", "))", "Skipped, key not checked: \(skipped.joined(separator: ", "))")) }
            modelSearchSummary = parts.joined(separator: " · ")
        }
    }

    /// Testing or saving a candidate counts as reviewing it.
    func markModelSeen(provider: AIProvider, id: String) {
        guard let index = modelCatalog.models.firstIndex(where: { $0.provider == provider && $0.modelID == id && $0.isNew }) else { return }
        modelCatalog.models[index].isNew = false
        modelCatalog.save()
    }

    func acknowledgeNewModels() {
        guard modelCatalog.newCount > 0 else { return }
        for index in modelCatalog.models.indices { modelCatalog.models[index].isNew = false }
        modelCatalog.save()
    }
}

/// Collects usage events from one test without sharing mutable state across tasks.
actor UsageCollector {
    private var reportedModel: String?
    private var cost: Double?
    func add(_ event: ProviderUsage) {
        reportedModel = event.reportedModel ?? reportedModel ?? event.model
        if let usd = UsagePricing.cost(for: event).usd { cost = (cost ?? 0) + usd }
    }
    func snapshot() -> (reportedModel: String?, costUSD: Double?) { (reportedModel, cost) }
}
