//
//  SettingsUnifiedProxySettingsSection.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UnifiedProxySettingsSection: View {
    @Environment(QuotaViewModel.self) var viewModel
    @State var modeManager = OperatingModeManager.shared
    @State var settingsAudit = SettingsAuditTrail.shared
    
    @State var isLoading = true
    @State var loadError: String?
    @State var isLoadingConfig = false  // Prevents onChange from firing during load
    
    @State var proxyURL = ""
    @State var routingStrategy = "round-robin"
    @State var switchProject = true
    @State var switchPreviewModel = true
    @State var requestRetry = 3
    @State var maxRetryInterval = 30
    @State var loggingToFile = true
    @State var requestLog = false
    @State var debugMode = false
    @State var openAICompatibilityEntries: [OpenAICompatibilityEntry] = []
    @State var geminiAPIKeyEntries: [GeminiAPIKeyEntry] = []
    @State var compatibilityConfigLoadError: String?
    @State var compatibilityConfigLastUpdatedAt: Date?
    @State var upstreamHitCounts = UpstreamHitCounts()
    @State var upstreamHitPreviousCounts = UpstreamHitCounts()
    @State var isLoadingUpstreamHitCounts = false
    @State var upstreamHitLoadError: String?
    @State var upstreamHitLastUpdatedAt: Date?
    @State var upstreamHitAutoRefreshTask: Task<Void, Never>?
    @State var vertexEditableDisplayName = ""
    @State var vertexEditablePrefix = ""
    @State var vertexEditableBaseURL = ""
    @State var vertexOriginalDisplayName = ""
    @State var vertexOriginalPrefix = ""
    @State var vertexOriginalBaseURL = ""
    @State var isSavingVertexRouteSource = false
    @State var lastProxyURLValue = ""
    @State var lastRoutingStrategyValue = "round-robin"
    @State var lastSwitchProjectValue = true
    @State var lastSwitchPreviewModelValue = true
    @State var lastRequestRetryValue = 3
    @State var lastMaxRetryIntervalValue = 30
    @State var lastLoggingToFileValue = true
    @State var lastRequestLogValue = false
    @State var lastDebugModeValue = false
    
    @State var proxyURLValidation: ProxyURLValidationResult = .empty
    @State var showHybridMappingEditor = false
    @State var editingHybridMappingNamespace: String?
    @State var hybridMappingNamespace = ""
    @State var hybridMappingBaseURL = ""
    @State var hybridMappingModelSetText = ""
    @State var hybridMappingNotes = ""
    @State var pendingDeleteHybridMapping: BaseURLNamespaceModelSet?
    @State var hybridMappingSyncError: String?
    @State var isHybridMappingSyncing = false
    @State var hybridMappingLastSyncedAt: Date?
    @State var hybridMappingActiveAction: HybridMappingAction?
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var feedbackDismissTask: Task<Void, Never>?

    enum HybridMappingAction: Equatable {
        case save
        case reseed
        case resetDefaults
        case delete(namespace: String)
        case retrySync
    }

    struct UpstreamHitCounts: Sendable {
        var vertex = 0
        var v0 = 0
        var gemini = 0
    }
    
    /// Check if API is available (proxy running for local, or connected for remote)
    var isAPIAvailable: Bool {
        if modeManager.isLocalProxyMode {
            return viewModel.proxyManager.proxyStatus.running && viewModel.apiClient != nil
        } else {
            // For remote mode, check both connection status AND apiClient
            // connectionStatus is observable, apiClient is not (@ObservationIgnored)
            if case .connected = modeManager.connectionStatus {
                return viewModel.apiClient != nil
            }
            return false
        }
    }
    
    /// Header title based on mode
    var sectionTitle: String {
        modeManager.isLocalProxyMode 
            ? "settings.proxySettings".localized()
            : "settings.remoteProxySettings".localized()
    }

    var vertexCandidateOpenAIEntries: [OpenAICompatibilityEntry] {
        openAICompatibilityEntries.filter { entry in
            Self.isLikelyVertexSource(entry.name)
                || Self.isLikelyVertexSource(entry.baseURL)
                || Self.isLikelyVertexSource(entry.prefix)
        }
    }

    var vertexPrimaryCandidateIndex: Int? {
        if let nameMatched = openAICompatibilityEntries.firstIndex(where: { Self.isLikelyVertexSource($0.name) }) {
            return nameMatched
        }
        if let prefixMatched = openAICompatibilityEntries.firstIndex(where: { Self.isLikelyVertexSource($0.prefix) }) {
            return prefixMatched
        }
        return openAICompatibilityEntries.firstIndex(where: { Self.isLikelyVertexSource($0.baseURL) })
    }

    var vertexPrimaryCandidate: OpenAICompatibilityEntry? {
        guard let index = vertexPrimaryCandidateIndex else { return nil }
        return openAICompatibilityEntries[index]
    }

    var openAICompatibilityCredentialCount: Int {
        openAICompatibilityEntries.reduce(0) { partial, entry in
            partial + (entry.apiKeyEntries?.count ?? 0)
        }
    }

    var vertexRoutedUsageSourceSummary: String {
        let sourceLine = "openai-compatibility: \(openAICompatibilityEntries.count) / gemini-api-key: \(geminiAPIKeyEntries.count)"
        return "Routed Usage，非官方剩余额度 · \(sourceLine)"
    }

    var isVertexBaseURLValid: Bool {
        Self.normalizedHTTPURLString(vertexEditableBaseURL) != nil
    }

    var vertexBaseURLValidationMessage: String? {
        let trimmed = vertexEditableBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "settings.vertexRoutedUsage.baseURLRequired".localized(fallback: "请填写 base-url。")
        }
        guard isVertexBaseURLValid else {
            return "settings.vertexRoutedUsage.baseURLInvalid".localized(fallback: "base-url 必须是合法 http/https URL。")
        }
        return nil
    }

    var isVertexSourceDraftDirty: Bool {
        let currentName = vertexEditableDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPrefix = vertexEditablePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentBaseURL = vertexEditableBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentName != vertexOriginalDisplayName
            || currentPrefix != vertexOriginalPrefix
            || currentBaseURL != vertexOriginalBaseURL
    }

    var isVertexSourceSaveDisabled: Bool {
        isSavingVertexRouteSource
            || vertexPrimaryCandidateIndex == nil
            || !isVertexBaseURLValid
            || !isVertexSourceDraftDirty
    }

    var parsedHybridMappingModelSet: [String] {
        parseModelSetInput(hybridMappingModelSetText)
    }

    var hybridMappingDraftValidationMessages: [String] {
        let trimmedNamespace = hybridMappingNamespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = hybridMappingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidBaseURL: Bool = {
            guard let url = URL(string: trimmedBaseURL) else { return false }
            return url.scheme != nil && url.host != nil
        }()

        var messages: [String] = []
        if trimmedNamespace.isEmpty {
            messages.append("settings.hybridNamespace.validation.namespace".localized())
        }
        if !hasValidBaseURL {
            messages.append("settings.hybridNamespace.validation.baseURL".localized())
        }
        if parsedHybridMappingModelSet.isEmpty {
            messages.append("settings.hybridNamespace.validation.modelSet".localized())
        }
        return messages
    }

    var isHybridMappingDraftValid: Bool {
        hybridMappingDraftValidationMessages.isEmpty
    }

    var isHybridMappingMutating: Bool {
        hybridMappingActiveAction != nil
    }

    var isHybridMappingSaveInProgress: Bool {
        hybridMappingActiveAction == .save
    }

    var isHybridMappingReseedInProgress: Bool {
        hybridMappingActiveAction == .reseed
    }

    var isHybridMappingResetInProgress: Bool {
        hybridMappingActiveAction == .resetDefaults
    }

    func isHybridMappingDeleteInProgress(namespace: String) -> Bool {
        if case let .delete(activeNamespace) = hybridMappingActiveAction {
            return activeNamespace == namespace
        }
        return false
    }

    var hybridMappingSheetTitle: String {
        editingHybridMappingNamespace == nil
            ? "settings.hybridNamespace.editor.addTitle".localized()
            : "settings.hybridNamespace.editor.editTitle".localized()
    }

    var hybridMappingSyncStatusText: String {
        if isHybridMappingSyncing {
            return "settings.hybridNamespace.syncing".localized()
        }
        if let error = hybridMappingSyncError, !error.isEmpty {
            return String(
                format: "settings.hybridNamespace.syncError".localized(),
                error
            )
        }
        if let last = hybridMappingLastSyncedAt {
            return String(
                format: "settings.hybridNamespace.syncedAt".localized(),
                last.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return "settings.hybridNamespace.syncPending".localized()
    }
    
    var body: some View {
        Group {
            if !isAPIAvailable {
                // Show placeholder when API is not available
                Section {
                    HStack {
                        Image(systemName: "network.slash")
                            .foregroundStyle(.secondary)
                        Text(modeManager.isLocalProxyMode
                             ? "settings.proxy.startToConfigureAdvanced".localized()
                             : "settings.remote.noConnection".localized())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(sectionTitle, systemImage: "slider.horizontal.3")
                }
            } else if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("settings.remote.loading".localized())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(sectionTitle, systemImage: "slider.horizontal.3")
                }
                .onAppear {
                    Task {
                        await loadConfig()
                    }
                }
            } else if let error = loadError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.semanticWarning)
                        Text(error)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("action.retry".localized()) {
                            Task {
                                await loadConfig()
                            }
                        }
                    }
                } header: {
                    Label(sectionTitle, systemImage: "slider.horizontal.3")
                }
            } else {
                upstreamProxySection
                routingStrategySection
                vertexRoutedUsageSourceSection
                upstreamHitRealtimePanelSection
                hybridNamespaceModelSetSection
                quotaExceededSection
                retryConfigurationSection
                loggingSection
            }
        }
        .sheet(isPresented: $showHybridMappingEditor) {
            HybridNamespaceModelSetEditorSheet(
                title: hybridMappingSheetTitle,
                namespace: $hybridMappingNamespace,
                baseURL: $hybridMappingBaseURL,
                modelSetText: $hybridMappingModelSetText,
                notes: $hybridMappingNotes,
                validationMessages: hybridMappingDraftValidationMessages,
                isSaving: isHybridMappingSaveInProgress,
                syncErrorMessage: isHybridMappingSaveInProgress ? hybridMappingSyncError : nil,
                isSaveDisabled: !isHybridMappingDraftValid,
                onSave: {
                    Task {
                        await persistHybridMappingEditorDraft()
                    }
                },
                onCancel: {
                    guard !isHybridMappingSaveInProgress else { return }
                    showHybridMappingEditor = false
                    resetHybridMappingEditorDraft()
                }
            )
        }
        .alert(
            "settings.hybridNamespace.delete.title".localized(),
            isPresented: Binding(
                get: { pendingDeleteHybridMapping != nil },
                set: { newValue in
                    if !newValue {
                        pendingDeleteHybridMapping = nil
                    }
                }
            )
        ) {
            Button("action.cancel".localized(), role: .cancel) {
                pendingDeleteHybridMapping = nil
            }
            Button("action.delete".localized(), role: .destructive) {
                guard let mapping = pendingDeleteHybridMapping else { return }
                pendingDeleteHybridMapping = nil
                Task {
                    await performHybridMappingMutation(.delete(namespace: mapping.namespace)) {
                        viewModel.removeBaseURLNamespaceModelSet(namespace: mapping.namespace)
                    }
                }
            }
        } message: {
            Text(
                String(
                    format: "settings.hybridNamespace.delete.message".localized(),
                    pendingDeleteHybridMapping?.namespace ?? ""
                )
            )
        }
        .overlay(alignment: .top) {
            if let feedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(feedbackIsError ? Color.semanticDanger : Color.semanticSuccess)
                    Text(feedbackMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder((feedbackIsError ? Color.semanticDanger : Color.semanticSuccess).opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.primary.opacity(0.1), radius: 8, x: 0, y: 3)
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(feedbackMessage)
            }
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
            stopUpstreamHitAutoRefresh()
        }
        .task(id: isAPIAvailable) {
            if isAPIAvailable {
                startUpstreamHitAutoRefresh()
                await refreshUpstreamHitCounts()
            } else {
                stopUpstreamHitAutoRefresh()
            }
        }
    }

    func showFeedback(_ message: String, isError: Bool = false) {
        feedbackDismissTask?.cancel()
        feedbackIsError = isError
        withAnimation(.easeOut(duration: 0.2)) {
            feedbackMessage = message
        }

        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    feedbackMessage = nil
                }
            }
        }
    }
    
    var upstreamProxySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("settings.upstreamProxy".localized()) {
                    TextField("", text: $proxyURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .accessibilityLabel("settings.upstreamProxy".localized())
                        .help("settings.upstreamProxy".localized())
                        .onChange(of: proxyURL) { _, newValue in
                            proxyURLValidation = ProxyURLValidator.validate(newValue)
                        }
                        .onSubmit {
                            Task { await saveProxyURL() }
                        }
                }
                
                if proxyURLValidation != .valid && proxyURLValidation != .empty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.semanticWarning)
                        Text((proxyURLValidation.localizationKey ?? "").localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("settings.upstreamProxy.placeholder".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("settings.upstreamProxy.title".localized(), systemImage: "network")
        }
    }
    
    var routingStrategySection: some View {
        Section {
            Picker("settings.routingStrategy".localized(), selection: $routingStrategy) {
                Text("settings.roundRobin".localized()).tag("round-robin")
                Text("settings.fillFirst".localized()).tag("fill-first")
            }
            .pickerStyle(.segmented)
            .onChange(of: routingStrategy) { _, newValue in
                guard !isLoadingConfig else { return }
                Task { await saveRoutingStrategy(newValue) }
            }
        } header: {
            Label("settings.routingStrategy".localized(), systemImage: "arrow.triangle.branch")
        } footer: {
            Text(routingStrategy == "round-robin"
                 ? "settings.roundRobinDesc".localized()
                 : "settings.fillFirstDesc".localized())
            .font(.caption)
        }
    }
    
    var quotaExceededSection: some View {
        Section {
            Toggle("settings.autoSwitchAccount".localized(), isOn: $switchProject)
                .onChange(of: switchProject) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveSwitchProject(newValue) }
                }
            Toggle("settings.autoSwitchPreview".localized(), isOn: $switchPreviewModel)
                .onChange(of: switchPreviewModel) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveSwitchPreviewModel(newValue) }
                }
        } header: {
            Label("settings.quotaExceededBehavior".localized(), systemImage: "exclamationmark.triangle")
        } footer: {
            Text("settings.quotaExceededHelp".localized())
                .font(.caption)
        }
    }
    
    var hybridNamespaceModelSetSection: some View {
        Section {
            if viewModel.baseURLNamespaceModelSets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("settings.hybridNamespace.empty".localized())
                            .foregroundStyle(.secondary)
                    }
                    Text("settings.hybridNamespace.help".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.baseURLNamespaceModelSets) { mapping in
                    HybridNamespaceModelSetCard(
                        mapping: mapping,
                        isActionsDisabled: isHybridMappingMutating,
                        isDeleteInProgress: isHybridMappingDeleteInProgress(namespace: mapping.namespace),
                        onEdit: { presentEditHybridMappingEditor(mapping) },
                        onDelete: { pendingDeleteHybridMapping = mapping }
                    )
                }
            }

            if let syncError = hybridMappingSyncError, !syncError.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            String(
                                format: "settings.hybridNamespace.syncError".localized(),
                                syncError
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button("action.retry".localized()) {
                            Task {
                                await retryHybridMappingsSync()
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isHybridMappingMutating)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    presentCreateHybridMappingEditor()
                } label: {
                    Label("settings.hybridNamespace.add".localized(), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(isHybridMappingMutating)

                Button {
                    Task {
                        await performHybridMappingMutation(.reseed) {
                            viewModel.seedBaseURLNamespaceModelSetsForCurrentTopology()
                        }
                    }
                } label: {
                    if isHybridMappingReseedInProgress {
                        HStack(spacing: 6) {
                            SmallProgressView()
                            Text("settings.hybridNamespace.syncing".localized())
                        }
                    } else {
                        Label("settings.hybridNamespace.reseed".localized(), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isHybridMappingMutating)

                Button {
                    Task {
                        await performHybridMappingMutation(.resetDefaults) {
                            viewModel.resetBaseURLNamespaceModelSetsToDefaults()
                        }
                    }
                } label: {
                    if isHybridMappingResetInProgress {
                        HStack(spacing: 6) {
                            SmallProgressView()
                            Text("settings.hybridNamespace.syncing".localized())
                        }
                    } else {
                        Label("settings.hybridNamespace.resetDefaults".localized(), systemImage: "arrow.counterclockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isHybridMappingMutating)

                if isHybridMappingSyncing && !isHybridMappingReseedInProgress && !isHybridMappingResetInProgress {
                    HStack(spacing: 6) {
                        SmallProgressView()
                        Text("settings.hybridNamespace.syncing".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("settings.hybridNamespace.title".localized(), systemImage: "square.stack.3d.up.fill")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.hybridNamespace.persistedHelp".localized())
                Text(hybridMappingSyncStatusText)
                    .foregroundStyle(hybridMappingSyncError == nil ? Color.secondary : Color.semanticWarning)
            }
            .font(.caption)
        }
    }

    var vertexRoutedUsageSourceSection: some View {
        Section {
            LabeledContent("settings.vertexRoutedUsage.sources".localized(fallback: "配置来源")) {
                Text(vertexRoutedUsageSourceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("settings.vertexRoutedUsage.openaiCompat".localized(fallback: "openai-compatibility 条目")) {
                Text("\(openAICompatibilityEntries.count)")
            }

            LabeledContent("settings.vertexRoutedUsage.vertexCandidates".localized(fallback: "疑似 Vertex 路由条目")) {
                Text("\(vertexCandidateOpenAIEntries.count)")
            }

            if vertexPrimaryCandidate != nil {
                LabeledContent("settings.vertexRoutedUsage.primaryCandidate".localized(fallback: "主 Vertex 条目")) {
                    Text("\((vertexPrimaryCandidateIndex ?? 0) + 1)")
                }

                LabeledContent("settings.vertexRoutedUsage.displayName".localized(fallback: "display name")) {
                    TextField(
                        "settings.vertexRoutedUsage.displayNamePlaceholder".localized(fallback: "可选"),
                        text: $vertexEditableDisplayName
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }

                LabeledContent("settings.vertexRoutedUsage.prefix".localized(fallback: "prefix")) {
                    TextField(
                        "settings.vertexRoutedUsage.prefixPlaceholder".localized(fallback: "可选"),
                        text: $vertexEditablePrefix
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }

                LabeledContent("settings.vertexRoutedUsage.baseURL".localized(fallback: "base-url")) {
                    TextField(
                        "https://...",
                        text: $vertexEditableBaseURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                }

                if let validationMessage = vertexBaseURLValidationMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.semanticWarning)
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await saveVertexRoutedUsageSource()
                        }
                    } label: {
                        if isSavingVertexRouteSource {
                            HStack(spacing: 6) {
                                SmallProgressView()
                                Text("action.saving".localized(fallback: "保存中"))
                            }
                        } else {
                            Text("action.save".localized(fallback: "保存"))
                        }
                    }
                    .disabled(isVertexSourceSaveDisabled)

                    if isVertexSourceDraftDirty && !isSavingVertexRouteSource {
                        Button("action.reset".localized(fallback: "重置")) {
                            refreshVertexRoutedUsageDraft()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                Text("settings.vertexRoutedUsage.noVertexEntry".localized(fallback: "未找到可编辑的 Vertex 路由条目。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("settings.vertexRoutedUsage.openaiCompatCreds".localized(fallback: "openai-compatibility 凭据数")) {
                Text("\(openAICompatibilityCredentialCount)")
            }

            LabeledContent("settings.vertexRoutedUsage.geminiKeys".localized(fallback: "gemini-api-key 条目")) {
                Text("\(geminiAPIKeyEntries.count)")
            }

            if let compatibilityConfigLastUpdatedAt {
                LabeledContent("settings.vertexRoutedUsage.updatedAt".localized(fallback: "最近刷新")) {
                    Text(compatibilityConfigLastUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            if let compatibilityConfigLoadError, !compatibilityConfigLoadError.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text(
                        String(
                            format: "settings.vertexRoutedUsage.loadError".localized(fallback: "配置读取失败：%@"),
                            compatibilityConfigLoadError
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label(
                "settings.vertexRoutedUsage.title".localized(fallback: "Vertex Routed Usage（非官方剩余额度）"),
                systemImage: "chart.bar.xaxis"
            )
        } footer: {
            Text(
                "settings.vertexRoutedUsage.help".localized(
                    fallback: "此处展示 Routed Usage 的配置来源快照，仅用于路由排查与运营观察，不代表官方剩余额度。"
                )
            )
            .font(.caption)
        }
    }

    var upstreamHitRealtimePanelSection: some View {
        Section {
            let currentTotal = upstreamHitCounts.vertex + upstreamHitCounts.v0 + upstreamHitCounts.gemini
            HStack(spacing: 12) {
                upstreamHitMetricPill(
                    title: "Vertex",
                    count: upstreamHitCounts.vertex,
                    previousCount: upstreamHitPreviousCounts.vertex,
                    totalCount: currentTotal,
                    color: .semanticDanger
                )
                upstreamHitMetricPill(
                    title: "V0",
                    count: upstreamHitCounts.v0,
                    previousCount: upstreamHitPreviousCounts.v0,
                    totalCount: currentTotal,
                    color: .semanticAccentSecondary
                )
                upstreamHitMetricPill(
                    title: "Gemini",
                    count: upstreamHitCounts.gemini,
                    previousCount: upstreamHitPreviousCounts.gemini,
                    totalCount: currentTotal,
                    color: .semanticInfo
                )
            }

            HStack(spacing: 10) {
                Button {
                    Task { await refreshUpstreamHitCounts() }
                } label: {
                    if isLoadingUpstreamHitCounts {
                        HStack(spacing: 6) {
                            SmallProgressView()
                            Text("action.refreshing".localized(fallback: "刷新中"))
                        }
                    } else {
                        Label("action.refresh".localized(fallback: "刷新"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoadingUpstreamHitCounts)

                Spacer()

                if let upstreamHitLastUpdatedAt {
                    Text(
                        String(
                            format: "settings.vertexHitPanel.updatedAt".localized(fallback: "最近更新时间：%@"),
                            upstreamHitLastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if isLoadingUpstreamHitCounts {
                    Text("settings.vertexHitPanel.loading".localized(fallback: "正在加载命中数据..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("settings.vertexHitPanel.notLoaded".localized(fallback: "尚未加载命中数据"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let upstreamHitLoadError, !upstreamHitLoadError.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text(
                        String(
                            format: "settings.vertexHitPanel.loadError".localized(fallback: "命中计数加载失败：%@"),
                            upstreamHitLoadError
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label(
                "settings.vertexHitPanel.title".localized(fallback: "当前命中上游实时计数"),
                systemImage: "bolt.horizontal.circle"
            )
        } footer: {
            Text(
                "settings.vertexHitPanel.help".localized(
                    fallback: "统计窗口：最近 15 分钟。优先按 provider/model/source 识别上游；无法明确识别的事件会归类为 other 并忽略，不计入三类命中。"
                )
            )
            .font(.caption)
        }
    }
    
    var retryConfigurationSection: some View {
        Section {
            Stepper("settings.maxRetries".localized() + ": \(requestRetry)", value: $requestRetry, in: 0...10)
                .onChange(of: requestRetry) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveRequestRetry(newValue) }
                }
            
            Stepper("settings.maxRetryInterval".localized() + ": \(maxRetryInterval)s", value: $maxRetryInterval, in: 5...300, step: 5)
                .onChange(of: maxRetryInterval) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveMaxRetryInterval(newValue) }
                }
        } header: {
            Label("settings.retryConfiguration".localized(), systemImage: "arrow.clockwise")
        } footer: {
            Text("settings.retryHelp".localized())
                .font(.caption)
        }
    }
    
    var loggingSection: some View {
        Section {
            Toggle("settings.loggingToFile".localized(), isOn: $loggingToFile)
                .onChange(of: loggingToFile) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveLoggingToFile(newValue) }
                }
            
            Toggle("settings.requestLog".localized(), isOn: $requestLog)
                .onChange(of: requestLog) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveRequestLog(newValue) }
                }
            
            Toggle("settings.debugMode".localized(), isOn: $debugMode)
                .onChange(of: debugMode) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveDebugMode(newValue) }
                }
        } header: {
            Label("settings.logging".localized(), systemImage: "doc.text")
        } footer: {
            Text("settings.loggingHelp".localized())
                .font(.caption)
        }
    }

    private static func isLikelyVertexSource(_ value: String?) -> Bool {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return false
        }
        return raw.contains("vertex")
            || raw.contains("aiplatform.googleapis.com")
            || raw.contains("googleapis.com")
    }

    static func normalizedHTTPURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return trimmed
    }

    func refreshVertexRoutedUsageDraft() {
        guard let candidate = vertexPrimaryCandidate else {
            vertexEditableDisplayName = ""
            vertexEditablePrefix = ""
            vertexEditableBaseURL = ""
            vertexOriginalDisplayName = ""
            vertexOriginalPrefix = ""
            vertexOriginalBaseURL = ""
            return
        }

        let normalizedName = candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedPrefix = candidate.prefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedBaseURL = candidate.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        vertexEditableDisplayName = normalizedName
        vertexEditablePrefix = normalizedPrefix
        vertexEditableBaseURL = normalizedBaseURL
        vertexOriginalDisplayName = normalizedName
        vertexOriginalPrefix = normalizedPrefix
        vertexOriginalBaseURL = normalizedBaseURL
    }

    @ViewBuilder
    private func upstreamHitMetricPill(
        title: String,
        count: Int,
        previousCount: Int,
        totalCount: Int,
        color: Color
    ) -> some View {
        let trendSymbol = Self.upstreamHitTrendSymbol(current: count, previous: previousCount)
        let shareText = Self.upstreamHitShareText(count: count, total: totalCount)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Text(shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(trendSymbol)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

}
