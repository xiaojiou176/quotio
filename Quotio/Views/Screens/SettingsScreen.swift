//
//  SettingsScreen.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modeManager = OperatingModeManager.shared
    @State private var showRestoreOriginalConfirmation = false
    @State private var applyWorkaroundActionState: TroubleshootingActionState = .idle
    @State private var applyWorkaroundResetTask: Task<Void, Never>?
    private let launchManager = LaunchAtLoginManager.shared

    private enum TroubleshootingActionState: Equatable {
        case idle
        case success
    }
    
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
                Button {
                    CLIProxyManager.shared.applyBaseURLWorkaround()
                    triggerApplyWorkaroundFeedback()
                } label: {
                    if applyWorkaroundActionState == .success {
                        Label("status.connected".localized(fallback: "已应用"), systemImage: "checkmark.seal.fill")
                    } else {
                        Label("troubleshooting.applyWorkaround".localized(), systemImage: "wrench.and.screwdriver")
                    }
                }
                .buttonStyle(MenuRowButtonStyle(hoverColor: Color.semanticInfo.opacity(0.14), cornerRadius: 8))
                .motionAwareAnimation(QuotioMotion.contentSwap, value: applyWorkaroundActionState)
                .motionAwareAnimation(QuotioMotion.successEmphasis, value: applyWorkaroundActionState == .success)

                Button {
                    showRestoreOriginalConfirmation = true
                } label: {
                    Label("troubleshooting.restoreOriginal".localized(), systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(MenuRowButtonStyle(hoverColor: Color.semanticDanger.opacity(0.12), cornerRadius: 8))
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

            // Motion rhythm profile
            MotionProfileSection()
            
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
        .onDisappear {
            applyWorkaroundResetTask?.cancel()
        }
    }

    private func triggerApplyWorkaroundFeedback() {
        applyWorkaroundResetTask?.cancel()
        withMotionAwareAnimation(QuotioMotion.successEmphasis, reduceMotion: reduceMotion) {
            applyWorkaroundActionState = .success
        }

        applyWorkaroundResetTask = Task {
            try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion) * 3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withMotionAwareAnimation(QuotioMotion.dismiss, reduceMotion: reduceMotion) {
                    applyWorkaroundActionState = .idle
                }
            }
        }
    }
}
