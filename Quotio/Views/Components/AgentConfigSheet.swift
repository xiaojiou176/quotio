//
//  AgentConfigSheet.swift
//  Quotio - Agent configuration modal with automatic/manual modes
//

import SwiftUI

struct AgentConfigSheet: View {
    @Bindable var viewModel: AgentSetupViewModel
    let agent: CLIAgent
    
    @Environment(\.dismiss) private var dismiss
    @State private var previewConfig: AgentConfigResult?
    @State private var showRestoreConfirm = false
    @State private var backupToRestore: AgentConfigurationService.BackupFile?
    
    private var hasResult: Bool {
        viewModel.configResult != nil
    }
    
    private var isSuccess: Bool {
        viewModel.configResult?.success == true
    }
    
    private var isManualMode: Bool {
        viewModel.configurationMode == .manual
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    if hasResult {
                        resultView
                    } else {
                        configurationView
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.automatic, axes: .vertical)
            
            Divider()
            
            footerView
        }
        .frame(width: 720, height: 600)
        .onAppear {
            viewModel.resetSheetState()
            if isManualMode {
                generatePreview()
            }
        }
        .onChange(of: viewModel.configurationMode) { _, newMode in
            if newMode == .manual {
                generatePreview()
            } else {
                previewConfig = nil
            }
        }
        .alert("common.error".localized(fallback: "错误"), isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("action.ok".localized(fallback: "确定")) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    private func generatePreview() {
        Task {
            previewConfig = await viewModel.generatePreviewConfig()
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(agent.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: agent.systemIcon)
                    .font(.title3)
                    .foregroundStyle(agent.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("agents.configure".localized() + " " + agent.displayName)
                    .font(.headline)
                
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                viewModel.dismissConfiguration()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.close".localized())
            .help("action.close".localized())
        }
        .padding(16)
    }
    
    private var configurationView: some View {
        VStack(spacing: 16) {
            setupModeSection
            
            modeSelectionSection
            
            if agent == .claudeCode && !isManualMode {
                storageOptionSection
            }
            
            // Only show proxy-specific options when in proxy mode
            if viewModel.selectedSetupMode == .proxy {
                connectionInfoSection
                
                if agent == .claudeCode {
                    modelSlotsSection
                }
                
                if agent == .geminiCLI {
                    oauthToggleSection
                }
                
                if isManualMode {
                    manualPreviewSection
                }
                
                testConnectionSection
            } else {
                defaultModeInfoSection
            }
            
            if !viewModel.availableBackups.isEmpty {
                backupSection
            }
        }
    }
    
    // MARK: - Setup Mode Section
    
    private var setupModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("agents.setupMode".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let saved = viewModel.savedConfig {
                    Label(
                        saved.isProxyConfigured ? "agents.currentlyProxy".localized() : "agents.currentlyDefault".localized(),
                        systemImage: saved.isProxyConfigured ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(saved.isProxyConfigured ? Color.semanticSuccess : .secondary)
                }
            }
            
            HStack(spacing: 12) {
                ForEach(ConfigurationSetup.allCases) { setup in
                    SetupModeButton(
                        setup: setup,
                        isSelected: viewModel.selectedSetupMode == setup,
                        action: {
                            viewModel.selectedSetupMode = setup
                            viewModel.currentConfiguration?.setupMode = setup
                        }
                    )
                }
            }
            
            Text(viewModel.selectedSetupMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var defaultModeInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agents.defaultSetup".localized())
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("agents.defaultSetup.info".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let saved = viewModel.savedConfig, saved.isProxyConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text("agents.proxyRemovalWarning".localized())
                        .font(.caption)
                        .foregroundStyle(Color.semanticWarning)
                }
                .padding(8)
                .background(Color.semanticWarning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Backup Section
    
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("agents.restoreBackup".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(String(format: "agents.availableBackups".localized(), viewModel.availableBackups.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availableBackups.prefix(5)) { backup in
                        BackupButton(backup: backup) {
                            backupToRestore = backup
                            showRestoreConfirm = true
                        }
                    }
                }
            }
            
            Text("agents.restoreBackup.info".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("agents.restoreBackup.confirm.title".localized(), isPresented: $showRestoreConfirm) {
            Button("action.cancel".localized(), role: .cancel) {
                backupToRestore = nil
            }
            if let backup = backupToRestore {
                Button("agents.restoreAction".localized(), role: .destructive) {
                    Task { await viewModel.restoreFromBackup(backup) }
                }
            }
        } message: {
            Text("agents.restoreBackup.confirm.message".localized())
        }
    }
    
    private var modeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agents.configMode".localized())
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 12) {
                ForEach(ConfigurationMode.allCases) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: viewModel.configurationMode == mode,
                        action: { viewModel.configurationMode = mode }
                    )
                }
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var storageOptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agents.storageOption".localized())
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 12) {
                ForEach(ConfigStorageOption.allCases) { option in
                    StorageOptionButton(
                        option: option,
                        isSelected: viewModel.configStorageOption == option,
                        action: { viewModel.configStorageOption = option }
                    )
                }
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var connectionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agents.connectionInfo".localized())
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(spacing: 6) {
                InfoRow(label: "agents.proxyURL".localized(), value: viewModel.currentConfiguration?.proxyURL ?? "")
                InfoRow(label: "agents.apiKey".localized(), value: maskedAPIKey, isMasked: true)
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var maskedAPIKey: String {
        guard let key = viewModel.currentConfiguration?.apiKey, key.count > 8 else {
            return "••••••••"
        }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }
    
    private var modelSlotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("agents.modelSlots".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button {
                    Task { await viewModel.loadModels(forceRefresh: true) }
                } label: {
                    if viewModel.isFetchingModels {
                        SmallProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .help("agents.refreshModels.help".localized(fallback: "从代理刷新模型列表"))
                .accessibilityLabel("agents.refreshModels".localized(fallback: "刷新模型"))
                .disabled(viewModel.isFetchingModels)
            }
            
            VStack(spacing: 8) {
                ForEach(ModelSlot.allCases) { slot in
                    ModelSlotRow(
                        slot: slot,
                        selectedModel: viewModel.currentConfiguration?.modelSlots[slot] ?? "",
                        availableModels: viewModel.availableModels,
                        onModelChange: { model in
                            viewModel.updateModelSlot(slot, model: model)
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var oauthToggleSection: some View {
        Toggle(isOn: Binding(
            get: { viewModel.currentConfiguration?.useOAuth ?? true },
            set: { viewModel.currentConfiguration?.useOAuth = $0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("agents.useOAuth".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("agents.useOAuthDesc".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var manualPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("agents.rawConfigs".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let config = previewConfig, !config.rawConfigs.isEmpty {
                    Button {
                        copyPreviewToClipboard()
                    } label: {
                        Label("action.copyAll".localized(), systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            if let config = previewConfig, !config.rawConfigs.isEmpty {
                if config.rawConfigs.count > 1 {
                    Picker("agents.previewConfig".localized(fallback: "配置"), selection: $viewModel.selectedRawConfigIndex) {
                        ForEach(config.rawConfigs.indices, id: \.self) { index in
                            Text(config.rawConfigs[index].filename ?? String(format: "agents.previewConfig.item".localized(fallback: "配置 %d"), index + 1))
                                .tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if viewModel.selectedRawConfigIndex < config.rawConfigs.count {
                    RawConfigView(config: config.rawConfigs[viewModel.selectedRawConfigIndex]) {
                        copyPreviewToClipboard(index: viewModel.selectedRawConfigIndex)
                    }
                }
            } else {
                HStack {
                    SmallProgressView()
                    Text("agents.preview.generating".localized(fallback: "正在生成预览..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func copyPreviewToClipboard(index: Int? = nil) {
        guard let config = previewConfig else { return }
        
        let content: String
        if let idx = index, idx < config.rawConfigs.count {
            content = config.rawConfigs[idx].content
        } else {
            content = config.rawConfigs.map { $0.content }.joined(separator: "\n\n---\n\n")
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    private var testConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("agents.testConnection".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button {
                    Task { await viewModel.testConnection() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isTesting {
                            SmallProgressView()
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text("agents.test".localized())
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isTesting)
            }
            
            if let result = viewModel.testResult {
                TestResultView(result: result)
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private var resultView: some View {
        if isSuccess {
            successResultView
        } else {
            errorResultView
        }
    }
    
    private var successResultView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.semanticSuccess)
                
                Text("agents.configSuccess".localized())
                    .font(.headline)
                    .foregroundStyle(Color.semanticSuccess)
            }
            
            if let result = viewModel.configResult {
                Text(result.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.semanticSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if result.mode == .automatic {
                    automaticModeResult(result)
                }
                
                if result.mode == .manual && !result.rawConfigs.isEmpty {
                    manualModeResult(result)
                }
            }
        }
    }
    
    private func automaticModeResult(_ result: AgentConfigResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agents.filesModified".localized())
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 6) {
                if let configPath = result.configPath {
                    FilePathRow(icon: "doc.fill", label: "agents.fileRow.config".localized(fallback: "配置"), path: configPath)
                }
                
                if let authPath = result.authPath {
                    FilePathRow(icon: "key.fill", label: "agents.fileRow.auth".localized(fallback: "鉴权"), path: authPath)
                }
                
                if result.shellConfig != nil {
                    FilePathRow(icon: "terminal", label: "agents.fileRow.shell".localized(fallback: "Shell"), path: viewModel.detectedShell.profilePath)
                }
                
                if let backupPath = result.backupPath {
                    FilePathRow(icon: "clock.arrow.circlepath", label: "agents.fileRow.backup".localized(fallback: "备份"), path: backupPath)
                }
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func manualModeResult(_ result: AgentConfigResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("agents.rawConfigs".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button {
                    viewModel.copyAllRawConfigsToClipboard()
                } label: {
                    Label("action.copyAll".localized(), systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if result.rawConfigs.count > 1 {
                Picker("agents.previewConfig".localized(fallback: "配置"), selection: $viewModel.selectedRawConfigIndex) {
                    ForEach(result.rawConfigs.indices, id: \.self) { index in
                        Text(result.rawConfigs[index].filename ?? String(format: "agents.previewConfig.item".localized(fallback: "配置 %d"), index + 1))
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            if viewModel.selectedRawConfigIndex < result.rawConfigs.count {
                RawConfigView(config: result.rawConfigs[viewModel.selectedRawConfigIndex]) {
                    viewModel.copyRawConfigToClipboard(index: viewModel.selectedRawConfigIndex)
                }
            }
        }
        .padding(16)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var errorResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.semanticDanger)
            
            Text("agents.configFailed".localized())
                .font(.headline)
                .foregroundStyle(Color.semanticDanger)
            
            if let error = viewModel.configResult?.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.semanticSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private var footerView: some View {
        HStack {
            if hasResult {
                Spacer()
                
                Button("action.done".localized()) {
                    viewModel.dismissConfiguration()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            } else {
                Button("action.cancel".localized(), role: .cancel) {
                    viewModel.dismissConfiguration()
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    Task { await viewModel.applyConfiguration() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isConfiguring {
                            SmallProgressView()
                        } else {
                            Image(systemName: viewModel.configurationMode == .automatic ? "gearshape.2" : "square.and.arrow.down")
                        }
                        Text(viewModel.configurationMode == .automatic ? "agents.apply".localized() : "agents.saveConfig".localized())
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(agent.color)
                .disabled(viewModel.isConfiguring)
                .keyboardShortcut(.return)
            }
        }
        .padding(16)
    }
}
