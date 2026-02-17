//
//  SettingsScreen.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var modeManager = OperatingModeManager.shared
    @State private var showRestoreOriginalConfirmation = false
    private let launchManager = LaunchAtLoginManager.shared
    
    var body: some View {
        @Bindable var lang = LanguageManager.shared

        Form {
            // Operating Mode
            OperatingModeSection()
            
            // Remote Server Configuration - Only in Remote Proxy Mode
            if modeManager.isRemoteProxyMode {
                RemoteServerSection()
                UnifiedProxySettingsSection()
            }

            // General Settings
            Section {
                LaunchAtLoginToggle()
            } header: {
                Label("settings.general".localized(), systemImage: "gearshape")
            }

            // Language
            Section {
                Picker(selection: Binding(
                    get: { lang.currentLanguage },
                    set: { lang.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        HStack {
                            Text(language.flag)
                            Text(language.displayName)
                        }
                        .tag(language)
                    }
                } label: {
                    Text("settings.language".localized())
                }
            } header: {
                Label("settings.language".localized(), systemImage: "globe")
            }

            // Troubleshooting
            Section {
                Button("troubleshooting.applyWorkaround".localized()) {
                    CLIProxyManager.shared.applyBaseURLWorkaround()
                }

                Button("troubleshooting.restoreOriginal".localized()) {
                    showRestoreOriginalConfirmation = true
                }
                .foregroundStyle(Color.semanticDanger)
            } header: {
                Label("troubleshooting.title".localized(), systemImage: "hammer.fill")
            } footer: {
                Text("troubleshooting.description".localized())
            }

            // Appearance
            AppearanceSettingsSection()

            // UI experience and accessibility
            UIExperienceSection()
            
            // Privacy
            PrivacySettingsSection()
            
            // Local Proxy Server - Only in Local Proxy Mode
            if modeManager.isLocalProxyMode {
                LocalProxyServerSection()
                UnifiedProxySettingsSection()
            }
            
            // Notifications
            NotificationSettingsSection()
            
            // Quota Display
            QuotaDisplaySettingsSection()
            
            // Usage Display
            UsageDisplaySettingsSection()
            
            // Refresh Cadence
            RefreshCadenceSettingsSection()
            
            // Menu Bar
            MenuBarSettingsSection()

            // Feature rollout controls
            FeatureFlagSection()

            // Local audit trail for critical settings changes
            SettingsAuditSection()
            
            // Paths - Only in Local Proxy Mode
            if modeManager.isLocalProxyMode {
                LocalPathsSection()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("nav.settings".localized())
        .confirmationDialog(
            "troubleshooting.restoreOriginal".localized(),
            isPresented: $showRestoreOriginalConfirmation,
            titleVisibility: .visible
        ) {
            Button("action.confirm".localized(fallback: "确认"), role: .destructive) {
                CLIProxyManager.shared.removeBaseURLWorkaround()
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("troubleshooting.restoreOriginal.message".localized(fallback: "此操作会移除当前修复方案并恢复原始行为。"))
        }
        .onAppear {
            Log.debug("[SettingsScreen] View appeared - mode: \(modeManager.currentMode.rawValue), proxy running: \(viewModel.proxyManager.proxyStatus.running)")
        }
    }
}

