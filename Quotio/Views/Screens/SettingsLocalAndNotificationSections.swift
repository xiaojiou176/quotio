//
//  SettingsLocalAndNotificationSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LocalProxyServerSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @AppStorage("autoStartProxy") private var autoStartProxy = false
    @AppStorage("autoStartTunnel") private var autoStartTunnel = false
    @AppStorage("autoRestartTunnel") private var autoRestartTunnel = false
    @AppStorage("allowNetworkAccess") private var allowNetworkAccess = false
    @State private var portText: String = ""
    @State private var isLoadingConfig = false  // Prevents onChange from firing during initial load
    
    var body: some View {
        Section {
            HStack {
                Text("settings.port".localized())
                Spacer()
                TextField("settings.port".localized(), text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: portText) { _, newValue in
                        guard !isLoadingConfig else { return }
                        if let port = UInt16(newValue), port > 0 {
                            viewModel.proxyManager.port = port
                        }
                    }
            }
            
            LabeledContent("settings.status".localized()) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.proxyManager.proxyStatus.running ? Color.semanticSuccess : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(viewModel.proxyManager.proxyStatus.running ? "status.running".localized() : "status.stopped".localized())
                }
            }
            
            LabeledContent("settings.endpoint".localized()) {
                Text(viewModel.proxyManager.proxyStatus.endpoint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            
            ManagementKeyRow()
            
            Toggle("settings.autoStartProxy".localized(), isOn: $autoStartProxy)
            
            Toggle("settings.autoStartTunnel".localized(), isOn: $autoStartTunnel)
                .disabled(!viewModel.tunnelManager.installation.isInstalled)
            
            Toggle("settings.autoRestartTunnel".localized(), isOn: $autoRestartTunnel)
                .disabled(!viewModel.tunnelManager.installation.isInstalled)
                
            NetworkAccessSection(allowNetworkAccess: $allowNetworkAccess)
                .onChange(of: allowNetworkAccess) { _, newValue in
                    guard !isLoadingConfig else { return }
                    viewModel.proxyManager.allowNetworkAccess = newValue
                }
                

        } header: {
            Label("settings.proxyServer".localized(), systemImage: "server.rack")
        } footer: {
            Text("settings.restartProxy".localized())
                .font(.caption)
        }
        .onAppear {
            isLoadingConfig = true
            portText = String(viewModel.proxyManager.port)
            // Delay clearing the flag to allow onChange to be suppressed
            DispatchQueue.main.async {
                isLoadingConfig = false
            }
        }
    }
}

struct NetworkAccessSection: View {
    @Binding var allowNetworkAccess: Bool
    
    var body: some View {
        Section {
            Toggle("settings.allowNetworkAccess".localized(), isOn: $allowNetworkAccess)
            
            LabeledContent("settings.bindAddress".localized()) {
                Text(allowNetworkAccess ? "0.0.0.0 (All Interfaces)" : "127.0.0.1 (Localhost)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(allowNetworkAccess ? Color.semanticWarning : .secondary)
            }
            
            if allowNetworkAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text("settings.networkAccessWarning".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("settings.networkAccess".localized(), systemImage: "network")
        } footer: {
            Text("settings.networkAccessFooter".localized())
                .font(.caption)
        }
    }
}

// MARK: - Local Paths Section

struct LocalPathsSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    
    var body: some View {
        Section {
            LabeledContent("settings.binary".localized()) {
                PathLabel(path: viewModel.proxyManager.effectiveBinaryPath)
            }
            
            LabeledContent("settings.config".localized()) {
                PathLabel(path: viewModel.proxyManager.configPath)
            }
            
            LabeledContent("settings.authDir".localized()) {
                PathLabel(path: viewModel.proxyManager.authDir)
            }
        } header: {
            Label("settings.paths".localized(), systemImage: "folder")
        }
    }
}

// MARK: - Path Label

struct PathLabel: View {
    let path: String
    
    var body: some View {
        HStack {
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(path, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("settings.path.copy".localized(fallback: "复制路径"))
            .accessibilityLabel("settings.path.copy".localized(fallback: "复制路径"))

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("settings.path.openFinder".localized(fallback: "在 Finder 中打开"))
            .accessibilityLabel("settings.path.openFinder".localized(fallback: "在 Finder 中打开"))
        }
    }
}

struct NotificationSettingsSection: View {
    private let notificationManager = NotificationManager.shared
    @State private var settingsAudit = SettingsAuditTrail.shared
    
    var body: some View {
        @Bindable var manager = notificationManager
        
        Section {
            Toggle("settings.notifications.enabled".localized(), isOn: Binding(
                get: { manager.notificationsEnabled },
                set: {
                    let old = manager.notificationsEnabled
                    manager.notificationsEnabled = $0
                    settingsAudit.recordChange(
                        key: "notifications.enabled",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.notifications"
                    )
                }
            ))
            
            if manager.notificationsEnabled {
                Toggle("settings.notifications.quotaLow".localized(), isOn: Binding(
                    get: { manager.notifyOnQuotaLow },
                    set: {
                        let old = manager.notifyOnQuotaLow
                        manager.notifyOnQuotaLow = $0
                        settingsAudit.recordChange(
                            key: "notifications.quota_low",
                            oldValue: String(old),
                            newValue: String($0),
                            source: "settings.notifications"
                        )
                    }
                ))
                
                Toggle("settings.notifications.cooling".localized(), isOn: Binding(
                    get: { manager.notifyOnCooling },
                    set: {
                        let old = manager.notifyOnCooling
                        manager.notifyOnCooling = $0
                        settingsAudit.recordChange(
                            key: "notifications.cooling",
                            oldValue: String(old),
                            newValue: String($0),
                            source: "settings.notifications"
                        )
                    }
                ))
                
                Toggle("settings.notifications.proxyCrash".localized(), isOn: Binding(
                    get: { manager.notifyOnProxyCrash },
                    set: {
                        let old = manager.notifyOnProxyCrash
                        manager.notifyOnProxyCrash = $0
                        settingsAudit.recordChange(
                            key: "notifications.proxy_crash",
                            oldValue: String(old),
                            newValue: String($0),
                            source: "settings.notifications"
                        )
                    }
                ))
                
                Toggle("settings.notifications.upgradeAvailable".localized(), isOn: Binding(
                    get: { manager.notifyOnUpgradeAvailable },
                    set: {
                        let old = manager.notifyOnUpgradeAvailable
                        manager.notifyOnUpgradeAvailable = $0
                        settingsAudit.recordChange(
                            key: "notifications.upgrade_available",
                            oldValue: String(old),
                            newValue: String($0),
                            source: "settings.notifications"
                        )
                    }
                ))
                
                HStack {
                    Text("settings.notifications.threshold".localized())
                    Spacer()
                    Picker("", selection: Binding(
                        get: { Int(manager.quotaAlertThreshold) },
                        set: {
                            let old = Int(manager.quotaAlertThreshold)
                            manager.quotaAlertThreshold = Double($0)
                            settingsAudit.recordChange(
                                key: "notifications.threshold",
                                oldValue: String(old),
                                newValue: String($0),
                                source: "settings.notifications"
                            )
                        }
                    )) {
                        Text("10%").tag(10)
                        Text("20%").tag(20)
                        Text("30%").tag(30)
                        Text("50%").tag(50)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .accessibilityLabel("settings.notifications.threshold".localized())
                    .help("settings.notifications.threshold".localized())
                }
            }
            
            if !manager.isAuthorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text("settings.notifications.notAuthorized".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("settings.notifications".localized(), systemImage: "bell")
        } footer: {
            Text("settings.notifications.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - Quota Display Settings Section

struct QuotaDisplaySettingsSection: View {
    @State private var settings = MenuBarSettingsManager.shared
    
    private var displayModeBinding: Binding<QuotaDisplayMode> {
        Binding(
            get: { settings.quotaDisplayMode },
            set: { settings.quotaDisplayMode = $0 }
        )
    }
    
    private var displayStyleBinding: Binding<QuotaDisplayStyle> {
        Binding(
            get: { settings.quotaDisplayStyle },
            set: { settings.quotaDisplayStyle = $0 }
        )
    }
    
    var body: some View {
        Section {
            Picker("settings.quota.displayMode".localized(), selection: displayModeBinding) {
                Text("settings.quota.displayMode.used".localized()).tag(QuotaDisplayMode.used)
                Text("settings.quota.displayMode.remaining".localized()).tag(QuotaDisplayMode.remaining)
            }
            .pickerStyle(.segmented)
            
            Picker("settings.quota.displayStyle".localized(), selection: displayStyleBinding) {
                ForEach(QuotaDisplayStyle.allCases) { style in
                    Text(style.localizationKey.localized()).tag(style)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Label("settings.quota.display".localized(), systemImage: "percent")
        } footer: {
            Text("settings.quota.display.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - Refresh Cadence Settings Section

struct RefreshCadenceSettingsSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var refreshSettings = RefreshSettingsManager.shared
    
    private var cadenceBinding: Binding<RefreshCadence> {
        Binding(
            get: { refreshSettings.refreshCadence },
            set: { refreshSettings.refreshCadence = $0 }
        )
    }
    
    var body: some View {
        Section {
            Picker("settings.refresh.cadence".localized(), selection: cadenceBinding) {
                ForEach(RefreshCadence.allCases) { cadence in
                    Text(cadence.localizationKey.localized()).tag(cadence)
                }
            }
            
            if refreshSettings.refreshCadence == .manual {
                Button {
                    Task {
                        await viewModel.manualRefresh()
                    }
                } label: {
                    Label("settings.refresh.now".localized(), systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Label("settings.refresh".localized(), systemImage: "clock.arrow.2.circlepath")
        } footer: {
            Text("settings.refresh.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - Update Settings Section

struct UpdateSettingsSection: View {
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    
    #if canImport(Sparkle)
    private let updaterService = UpdaterService.shared
    #endif
    
    var body: some View {
        Section {
            #if canImport(Sparkle)
            Toggle("settings.autoCheckUpdates".localized(), isOn: $autoCheckUpdates)
                .onChange(of: autoCheckUpdates) { _, newValue in
                    updaterService.automaticallyChecksForUpdates = newValue
                }
            
            HStack {
                Text("settings.lastChecked".localized())
                Spacer()
                if let date = updaterService.lastUpdateCheckDate {
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("settings.never".localized())
                        .foregroundStyle(.secondary)
                }
            }
            
            Button("settings.checkNow".localized()) {
                updaterService.checkForUpdates()
            }
            .disabled(!updaterService.canCheckForUpdates)
            #else
            Text("settings.version".localized() + ": " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
            #endif
        } header: {
            Label("settings.updates".localized(), systemImage: "arrow.down.circle")
        }
    }
}

// MARK: - Proxy Update Settings Section

