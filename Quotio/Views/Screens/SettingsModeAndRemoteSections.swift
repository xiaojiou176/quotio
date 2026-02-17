//
//  SettingsModeAndRemoteSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OperatingModeSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var modeManager = OperatingModeManager.shared
    @State private var showModeChangeConfirmation = false
    @State private var pendingMode: OperatingMode?
    @State private var showRemoteConfigSheet = false
    
    var body: some View {
        Section {
            // Mode selection cards
            VStack(spacing: 12) {
                ForEach(OperatingMode.allCases) { mode in
                    OperatingModeCard(
                        mode: mode,
                        isSelected: modeManager.currentMode == mode
                    ) {
                        handleModeSelection(mode)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("settings.appMode".localized(), systemImage: "switch.2")
        } footer: {
            footerText
        }
        .alert("settings.appMode.switchConfirmTitle".localized(), isPresented: $showModeChangeConfirmation) {
            Button("action.cancel".localized(), role: .cancel) {
                pendingMode = nil
            }
            Button("action.switch".localized()) {
                if let mode = pendingMode {
                    switchToMode(mode)
                }
                pendingMode = nil
            }
        } message: {
            Text("settings.appMode.switchConfirmMessage".localized())
        }
        .sheet(isPresented: $showRemoteConfigSheet) {
            RemoteConnectionSheet(
                existingConfig: modeManager.remoteConfig
            ) { config, managementKey in
                modeManager.switchToRemote(config: config, managementKey: managementKey)
                Task {
                    await viewModel.initialize()
                }
            }
            .environment(viewModel)
        }
    }
    
    @ViewBuilder
    private var footerText: some View {
        switch modeManager.currentMode {
        case .monitor:
            Label("settings.appMode.quotaOnlyNote".localized(), systemImage: "info.circle")
                .font(.caption)
        case .remoteProxy:
            Label("settings.appMode.remoteNote".localized(), systemImage: "info.circle")
                .font(.caption)
        case .localProxy:
            EmptyView()
        }
    }
    
    private func handleModeSelection(_ mode: OperatingMode) {
        guard mode != modeManager.currentMode else { return }
        
        // If switching to remote and no config exists, show config sheet
        if mode == .remoteProxy && modeManager.remoteConfig == nil {
            showRemoteConfigSheet = true
            return
        }
        
        // Confirm when switching FROM local proxy mode (stops the local proxy)
        if modeManager.currentMode == .localProxy && (mode == .monitor || mode == .remoteProxy) {
            pendingMode = mode
            showModeChangeConfirmation = true
        } else {
            // Switch immediately for other transitions
            switchToMode(mode)
        }
    }
    
    private func switchToMode(_ mode: OperatingMode) {
        modeManager.switchMode(to: mode) {
            viewModel.stopProxy()
        }
        
        // Re-initialize based on new mode
        Task {
            await viewModel.initialize()
        }
    }
}

// MARK: - Remote Server Section

struct RemoteServerSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var showRemoteConfigSheet = false
    @State private var isReconnecting = false
    @State private var modeManager = OperatingModeManager.shared
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var feedbackDismissTask: Task<Void, Never>?

    var body: some View {
        Section {
            // Remote configuration row
            remoteConfigRow
            
            // Connection status
            connectionStatusRow
        } header: {
            HStack(spacing: 8) {
                Label("settings.remoteServer.title".localized(), systemImage: "network")
                ExperimentalBadge()
            }
        } footer: {
            Text("settings.remoteServer.help".localized())
                .font(.caption)
        }
        .sheet(isPresented: $showRemoteConfigSheet) {
            RemoteConnectionSheet(
                existingConfig: modeManager.remoteConfig
            ) { config, managementKey in
                saveRemoteConfig(config, managementKey: managementKey)
            }
            .environment(viewModel)
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
        }
    }
    
    // MARK: - Remote Config Row
    
    private var remoteConfigRow: some View {
        HStack {
            if let config = modeManager.remoteConfig {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(config.endpointURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("settings.remoteServer.notConfigured".localized())
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("settings.remoteServer.configure".localized()) {
                showRemoteConfigSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - Connection Status Row
    
    private var connectionStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.subheadline)
            
            Spacer()
            
            if shouldShowReconnectButton {
                Button {
                    reconnect()
                } label: {
                    if isReconnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("action.reconnect".localized(), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isReconnectDisabled)
                .help(reconnectHintText)
                .accessibilityHint(reconnectHintText)
            }
        }
    }
    
    private var shouldShowReconnectButton: Bool {
        switch modeManager.connectionStatus {
        case .disconnected, .error:
            return true
        default:
            return false
        }
    }

    private var isReconnectDisabled: Bool {
        isReconnecting || !modeManager.hasValidRemoteConfig
    }

    private var reconnectHintText: String {
        if isReconnecting {
            return "settings.remoteServer.reconnecting".localized(fallback: "正在重连远端服务…")
        }
        if !modeManager.hasValidRemoteConfig {
            return "settings.remoteServer.configureBeforeReconnect".localized(fallback: "请先配置有效的远端服务。")
        }
        return "action.reconnect".localized()
    }
    
    private var statusColor: Color {
        switch modeManager.connectionStatus {
        case .connected: return Color.semanticSuccess
        case .connecting: return Color.semanticWarning
        case .disconnected: return .gray
        case .error: return Color.semanticDanger
        }
    }
    
    private var statusText: String {
        switch modeManager.connectionStatus {
        case .connected: return "status.connected".localized()
        case .connecting: return "status.connecting".localized()
        case .disconnected: return "status.disconnected".localized()
        case .error(let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty ? "status.error".localized(fallback: "错误") : trimmedMessage
        }
    }
    
    // MARK: - Actions
    
    private func saveRemoteConfig(_ config: RemoteConnectionConfig, managementKey: String) {
        let previousStatus = modeManager.connectionStatus
        modeManager.switchToRemote(config: config, managementKey: managementKey)
        
        Task { @MainActor in
            await viewModel.initialize()
            handlePostRemoteActionFeedback(previousStatus: previousStatus, action: .saveConfig)
        }
    }
    
    private func reconnect() {
        guard !isReconnectDisabled else {
            showFeedback(reconnectHintText, isError: true)
            return
        }

        isReconnecting = true

        Task { @MainActor in
            let previousStatus = modeManager.connectionStatus
            defer { isReconnecting = false }
            await viewModel.reconnectRemote()
            handlePostRemoteActionFeedback(previousStatus: previousStatus, action: .reconnect)
        }
    }

    @MainActor
    private func handlePostRemoteActionFeedback(previousStatus: ConnectionStatus, action: RemoteAction) {
        if action == .reconnect, modeManager.connectionStatus == previousStatus {
            showFeedback(
                "settings.remoteServer.reconnectNoChange".localized(fallback: "连接状态未变化，请检查远端服务状态。"),
                isError: true
            )
            return
        }

        switch modeManager.connectionStatus {
        case .connected:
            let successMessage = action == .saveConfig
                ? "settings.remoteServer.saveSuccess".localized(fallback: "远端配置已保存并连接成功。")
                : "settings.remoteServer.reconnectSuccess".localized(fallback: "远端服务已重新连接。")
            showFeedback(successMessage)
        case .error(let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackMessage = action == .saveConfig
                ? "保存配置后连接失败，请检查地址或管理密钥。"
                : "远端重连失败，请检查网络连接或管理密钥。"
            showFeedback(trimmedMessage.isEmpty ? fallbackMessage : trimmedMessage, isError: true)
        case .disconnected:
            let disconnectedMessage = action == .saveConfig
                ? "settings.remoteServer.disconnectedAfterSave".localized(fallback: "配置已保存，但当前仍未连接到远端服务。")
                : "settings.remoteServer.disconnectedAfterReconnect".localized(fallback: "重连后仍未连接，请稍后重试。")
            showFeedback(disconnectedMessage, isError: true)
        case .connecting:
            showFeedback("settings.remoteServer.reconnecting".localized(fallback: "正在重连远端服务…"))
        }
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
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
}

private enum RemoteAction {
    case saveConfig
    case reconnect
}

// MARK: - Unified Proxy Settings Section
// Works for both Local Proxy and Remote Proxy modes
// Uses ManagementAPIClient for hot-reload settings
