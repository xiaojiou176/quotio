//
//  SettingsDisplayAndAuditSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MenuBarSettingsSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    private let settings = MenuBarSettingsManager.shared
    @AppStorage("showInDock") private var showInDock = true
    @State private var showTruncationAlert = false
    @State private var pendingMaxItems: Int?
    
    private var showMenuBarIconBinding: Binding<Bool> {
        Binding(
            get: { settings.showMenuBarIcon },
            set: { newValue in
                // Prevent disabling both dock and menu bar icon (user would have no way to access app)
                if !newValue && !showInDock {
                    // Re-enable dock if user tries to disable menu bar icon while dock is already disabled
                    showInDock = true
                    // activation policy will be set by showInDockBinding automatically
                }
                settings.showMenuBarIcon = newValue
            }
        )
    }

    private var showInDockBinding: Binding<Bool> {
        Binding(
            get: { showInDock },
            set: { newValue in
                // Prevent disabling both dock and menu bar icon (user would have no way to access app)
                if !newValue && !settings.showMenuBarIcon {
                    // Re-enable menu bar icon if user tries to disable dock while menu bar is already disabled
                    settings.showMenuBarIcon = true
                }

                // Update the value
                showInDock = newValue

                // This is the ONLY place where activation policy is changed based on user settings
                // - true: dock icon always visible, even when window is closed
                // - false: dock icon never visible
                NSApp.setActivationPolicy(newValue ? .regular : .accessory)
            }
        )
    }
    
    private var showQuotaBinding: Binding<Bool> {
        Binding(
            get: { settings.showQuotaInMenuBar },
            set: { settings.showQuotaInMenuBar = $0 }
        )
    }
    
    private var colorModeBinding: Binding<MenuBarColorMode> {
        Binding(
            get: { settings.colorMode },
            set: { settings.colorMode = $0 }
        )
    }
    
    private var maxItemsBinding: Binding<Int> {
        Binding(
            get: { settings.menuBarMaxItems },
            set: { newValue in
                let clamped = min(max(newValue, MenuBarSettingsManager.minMenuBarItems), MenuBarSettingsManager.maxMenuBarItems)

                // Check if reducing max items would truncate current selection
                if clamped < settings.menuBarMaxItems && settings.selectedItems.count > clamped {
                    pendingMaxItems = clamped
                    showTruncationAlert = true
                } else {
                    settings.menuBarMaxItems = clamped
                    viewModel.syncMenuBarSelection()
                }
            }
        )
    }
    
    var body: some View {
        Section {
            Toggle("settings.showInDock".localized(), isOn: showInDockBinding)
            
            Toggle("settings.menubar.showIcon".localized(), isOn: showMenuBarIconBinding)
            
            if settings.showMenuBarIcon {
                Toggle("settings.menubar.showQuota".localized(), isOn: showQuotaBinding)
                
                if settings.showQuotaInMenuBar {
                    HStack {
                        Text("settings.menubar.maxItems".localized())
                        Spacer()
                        Text("\(settings.menuBarMaxItems)")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Stepper(
                            "",
                            value: maxItemsBinding,
                            in: MenuBarSettingsManager.minMenuBarItems...MenuBarSettingsManager.maxMenuBarItems,
                            step: 1
                        )
                        .labelsHidden()
                    }
                    
                    Picker("settings.menubar.colorMode".localized(), selection: colorModeBinding) {
                        Text("settings.menubar.colored".localized()).tag(MenuBarColorMode.colored)
                        Text("settings.menubar.monochrome".localized()).tag(MenuBarColorMode.monochrome)
                    }
                    .pickerStyle(.segmented)
                }
            }
        } header: {
            Label("settings.menubar".localized(), systemImage: "menubar.rectangle")
        } footer: {
            Text(String(
                format: "settings.menubar.help".localized(),
                settings.menuBarMaxItems
            ))
            .font(.caption)
        }
        .alert("menubar.truncation.title".localized(), isPresented: $showTruncationAlert) {
            Button("action.cancel".localized(), role: .cancel) {
                pendingMaxItems = nil
            }
            Button("action.ok".localized(), role: .destructive) {
                if let newMax = pendingMaxItems {
                    settings.menuBarMaxItems = newMax
                    viewModel.syncMenuBarSelection()
                    pendingMaxItems = nil
                }
            }
        } message: {
            if let newMax = pendingMaxItems {
                Text(String(
                    format: "menubar.truncation.message".localized(),
                    settings.selectedItems.count,
                    newMax
                ))
            }
        }
    }
}

// MARK: - Appearance Settings Section

struct AppearanceSettingsSection: View {
    @State private var appearanceManager = AppearanceManager.shared
    
    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { appearanceManager.appearanceMode },
            set: { appearanceManager.appearanceMode = $0 }
        )
    }
    
    var body: some View {
        Section {
            Picker("settings.appearance.mode".localized(), selection: appearanceModeBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.localizationKey.localized(), systemImage: mode.icon)
                        .tag(mode)
                }
            }
        } header: {
            Label("settings.appearance.title".localized(), systemImage: "paintbrush")
        } footer: {
            Text("settings.appearance.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - UI Experience Section

struct UIExperienceSection: View {
    @State private var settings = UIExperienceSettingsManager.shared
    @State private var settingsAudit = SettingsAuditTrail.shared

    private var densityBinding: Binding<InformationDensity> {
        Binding(
            get: { settings.informationDensity },
            set: {
                let old = settings.informationDensity
                settings.informationDensity = $0
                settingsAudit.recordChange(
                    key: "ui.information_density",
                    oldValue: old.rawValue,
                    newValue: $0.rawValue,
                    source: "settings.ui_experience"
                )
            }
        )
    }

    var body: some View {
        Section {
            Picker("settings.density.title".localized(fallback: "信息密度"), selection: densityBinding) {
                ForEach(InformationDensity.allCases) { mode in
                    Text(mode.localizationKey.localized(fallback: mode.rawValue)).tag(mode)
                }
            }

            Toggle("settings.a11y.highContrast".localized(fallback: "高对比度模式"), isOn: Binding(
                get: { settings.highContrastEnabled },
                set: {
                    let old = settings.highContrastEnabled
                    settings.highContrastEnabled = $0
                    settingsAudit.recordChange(
                        key: "ui.high_contrast",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.ui_experience"
                    )
                }
            ))

            Toggle("settings.a11y.largerText".localized(fallback: "更大字号"), isOn: Binding(
                get: { settings.largerTextEnabled },
                set: {
                    let old = settings.largerTextEnabled
                    settings.largerTextEnabled = $0
                    settingsAudit.recordChange(
                        key: "ui.larger_text",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.ui_experience"
                    )
                }
            ))

            Toggle("settings.a11y.visibleFocus".localized(fallback: "显示键盘焦点"), isOn: Binding(
                get: { settings.visibleFocusRingEnabled },
                set: {
                    let old = settings.visibleFocusRingEnabled
                    settings.visibleFocusRingEnabled = $0
                    settingsAudit.recordChange(
                        key: "ui.visible_focus_ring",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.ui_experience"
                    )
                }
            ))

            Toggle("settings.debug.capturePayload".localized(fallback: "捕获请求Payload证据（脱敏）"), isOn: Binding(
                get: { settings.captureRequestPayloadEvidence },
                set: {
                    let old = settings.captureRequestPayloadEvidence
                    settings.captureRequestPayloadEvidence = $0
                    settingsAudit.recordChange(
                        key: "ui.capture_payload_evidence",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.ui_experience"
                    )
                }
            ))
        } header: {
            Label("settings.uiExperience".localized(fallback: "UI 体验"), systemImage: "rectangle.compress.vertical")
        } footer: {
            Text("settings.uiExperience.help".localized(fallback: "用于改善阅读密度、键盘导航与视觉可达性。"))
                .font(.caption)
        }
    }
}

// MARK: - Feature Flags Section

struct FeatureFlagSection: View {
    @State private var flags = FeatureFlagManager.shared
    @State private var settingsAudit = SettingsAuditTrail.shared

    var body: some View {
        Section {
            Toggle("settings.flags.enhancedUI".localized(fallback: "启用增强布局"), isOn: Binding(
                get: { flags.enhancedUILayout },
                set: {
                    let old = flags.enhancedUILayout
                    flags.enhancedUILayout = $0
                    settingsAudit.recordChange(
                        key: "feature.enhanced_ui_layout",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.feature_flags"
                    )
                }
            ))
            Toggle("settings.flags.observability".localized(fallback: "启用观测联动"), isOn: Binding(
                get: { flags.enhancedObservability },
                set: {
                    let old = flags.enhancedObservability
                    flags.enhancedObservability = $0
                    settingsAudit.recordChange(
                        key: "feature.enhanced_observability",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.feature_flags"
                    )
                }
            ))
            Toggle("settings.flags.accessibility".localized(fallback: "启用无障碍强化"), isOn: Binding(
                get: { flags.accessibilityHardening },
                set: {
                    let old = flags.accessibilityHardening
                    flags.accessibilityHardening = $0
                    settingsAudit.recordChange(
                        key: "feature.accessibility_hardening",
                        oldValue: String(old),
                        newValue: String($0),
                        source: "settings.feature_flags"
                    )
                }
            ))
        } header: {
            Label("settings.flags.title".localized(fallback: "功能灰度"), systemImage: "testtube.2")
        } footer: {
            Text("settings.flags.help".localized(fallback: "用于分批发布新 UI、观测和无障碍能力。"))
                .font(.caption)
        }
    }
}

// MARK: - Settings Audit Section

struct SettingsAuditSection: View {
    @State private var audit = SettingsAuditTrail.shared
    @State private var showClearConfirmation = false
    @State private var searchText = ""

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        Section {
            TextField("settings.audit.searchPlaceholder".localized(fallback: "搜索设置项"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            if audit.events.isEmpty {
                Text("settings.audit.empty".localized(fallback: "暂无设置变更记录"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(humanizedKey(event.key))
                            .font(.caption.bold())
                        Text("\(event.oldValue) → \(event.newValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Self.formatter.string(from: event.timestamp)) · \(event.source)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            HStack {
                Button("settings.audit.export".localized(fallback: "导出审计记录")) {
                    exportAudit()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("settings.audit.clear".localized(fallback: "清空")) {
                    showClearConfirmation = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.semanticDanger)
            }
        } header: {
            Label("settings.audit.title".localized(fallback: "设置审计"), systemImage: "doc.badge.clock")
        } footer: {
            Text("settings.audit.help".localized(fallback: "记录关键设置项变更（前值、后值、时间、来源页面）。"))
                .font(.caption)
        }
        .confirmationDialog(
            "settings.audit.clear".localized(fallback: "清空审计"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("action.confirm".localized(fallback: "确认"), role: .destructive) {
                audit.clear()
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("settings.audit.clear.warning".localized(fallback: "清空后无法恢复，建议先导出审计记录。"))
        }
    }

    private func exportAudit() {
        do {
            let data = try audit.exportData()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "quotio-settings-audit-\(Date().ISO8601Format()).json"
            panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            Log.error("[SettingsAuditSection] Failed to export audit trail: \(error.localizedDescription)")
        }
    }

    private var filteredEvents: [SettingsAuditEvent] {
        let recent = audit.recent(limit: 20)
        guard !searchText.isEmpty else { return recent }
        let q = searchText.lowercased()
        return recent.filter { event in
            event.key.lowercased().contains(q)
            || event.source.lowercased().contains(q)
            || event.newValue.lowercased().contains(q)
            || event.oldValue.lowercased().contains(q)
        }
    }

    private func humanizedKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " / ")
            .capitalized
    }
}

// MARK: - Privacy Settings Section

struct PrivacySettingsSection: View {
    @State private var settings = MenuBarSettingsManager.shared
    
    private var hideSensitiveBinding: Binding<Bool> {
        Binding(
            get: { settings.hideSensitiveInfo },
            set: { settings.hideSensitiveInfo = $0 }
        )
    }
    
    var body: some View {
        Section {
            Toggle("settings.privacy.hideSensitive".localized(), isOn: hideSensitiveBinding)
        } header: {
            Label("settings.privacy".localized(), systemImage: "eye.slash")
        } footer: {
            Text("settings.privacy.hideSensitiveHelp".localized())
                .font(.caption)
        }
    }
}

