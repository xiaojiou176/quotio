//
//  SettingsAboutAndGeneralComponents.swift
//  Quotio
//

import SwiftUI
import AppKit

// MARK: - Version Badge

struct VersionBadge: View {
    let label: String
    let value: String
    let icon: String
    
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
        } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(isHovered ? Color.semanticInfo : .secondary)
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isHovered ? Color.semanticInfo : .secondary)
                
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isHovered ? Color.semanticInfo.opacity(0.1) : Color.secondary.opacity(0.05),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isHovered ? Color.semanticInfo.opacity(0.3) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withMotionAwareAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - About Update Card

struct AboutUpdateCard: View {
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    #if canImport(Sparkle)
    private let updaterService = UpdaterService.shared
    #endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(Color.semanticInfo)
                Text("settings.updates".localized())
                    .font(.headline)
                Spacer()
            }
            
            #if canImport(Sparkle)
            HStack {
                Text("settings.autoCheckUpdates".localized())
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: $autoCheckUpdates)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("settings.autoCheckUpdates".localized())
                    .help("settings.autoCheckUpdates".localized())
                    .onChange(of: autoCheckUpdates) { _, newValue in
                        updaterService.automaticallyChecksForUpdates = newValue
                    }
            }
            
            HStack {
                Text("settings.updateChannel.receiveBeta".localized())
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { updaterService.updateChannel == .beta },
                    set: { newValue in
                        updaterService.updateChannel = newValue ? .beta : .stable
                    }
                ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("settings.updateChannel.receiveBeta".localized())
                    .help("settings.updateChannel.receiveBeta".localized())
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
                
                Button("settings.checkNow".localized()) {
                    updaterService.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            #else
            Text("settings.version".localized() + ": " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                .font(.caption)
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(
            color: Color.primary.opacity(isHovered ? 0.08 : 0.04),
            radius: isHovered ? 8 : 4,
            x: 0,
            y: isHovered ? 2 : 1
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withMotionAwareAnimation(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - About Proxy Update Card

struct AboutProxyUpdateCard: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAdvancedSheet = false
    @State private var isCheckingForUpdate = false
    @State private var isUpgrading = false
    @State private var upgradeError: String?

    private var proxyManager: CLIProxyManager {
        viewModel.proxyManager
    }

    private var atomFeedService: AtomFeedUpdateService {
        AtomFeedUpdateService.shared
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.title3)
                    .foregroundStyle(Color.semanticAccentSecondary)
                Text("settings.proxyUpdate".localized())
                    .font(.headline)
                Spacer()
            }
            
            // Current version row
            HStack {
                Text("settings.proxyUpdate.currentVersion".localized())
                if let version = proxyManager.currentVersion ?? proxyManager.installedProxyVersion {
                    Text("v\(version)")
                        .font(.system(.subheadline).monospaced())
                        .fontWeight(.medium)
                } else {
                    Text("settings.proxyUpdate.unknown".localized())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            // Upgrade status with action buttons
            if proxyManager.upgradeAvailable, let upgrade = proxyManager.availableUpgrade {
                HStack {
                    Label {
                        Text("v\(upgrade.version) " + "settings.proxyUpdate.available".localized())
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Color.semanticSuccess)
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    Button {
                        performUpgrade(to: upgrade)
                    } label: {
                        ZStack {
                            Text("action.update".localized())
                                .opacity(isUpgrading ? 0 : 1)
                            
                            if isUpgrading {
                                SmallProgressView()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isUpgrading || !proxyManager.proxyStatus.running)
                }
            } else {
                HStack {
                    Label {
                        Text("settings.proxyUpdate.upToDate".localized())
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticSuccess)
                    }
                    .font(.caption)
                    
                    Spacer()
                    
                    Button {
                        checkForUpdate()
                    } label: {
                        ZStack {
                            Text("settings.proxyUpdate.checkNow".localized())
                                .opacity(isCheckingForUpdate ? 0 : 1)
                            
                            if isCheckingForUpdate {
                                SmallProgressView()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCheckingForUpdate)
                }

                // Last checked time
                if let lastCheck = atomFeedService.lastCLIProxyCheck {
                    HStack {
                        Text("settings.lastChecked".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Error message
            if let error = upgradeError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Proxy must be running hint (only for Update action, not Check)
            if proxyManager.upgradeAvailable && !proxyManager.proxyStatus.running {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.semanticInfo)
                    Text("settings.proxyUpdate.proxyMustRun".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Spacer()
                
                Button {
                    showAdvancedSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text("settings.proxyUpdate.advanced".localized())
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(
            color: Color.primary.opacity(isHovered ? 0.08 : 0.04),
            radius: isHovered ? 8 : 4,
            x: 0,
            y: isHovered ? 2 : 1
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withMotionAwareAnimation(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showAdvancedSheet) {
            ProxyVersionManagerSheet()
                .environment(viewModel)
        }
    }
    
    private func checkForUpdate() {
        isCheckingForUpdate = true
        upgradeError = nil

        Task { @MainActor in
            defer {
                // Always reset loading state
                isCheckingForUpdate = false
            }

            await proxyManager.checkForUpgrade()
        }
    }
    
    private func performUpgrade(to version: ProxyVersionInfo) {
        isUpgrading = true
        upgradeError = nil
        
        Task { @MainActor in
            do {
                try await proxyManager.performManagedUpgrade(to: version)
                isUpgrading = false
            } catch {
                upgradeError = error.localizedDescription
                isUpgrading = false
            }
        }
    }
}

// MARK: - Link Card

struct LinkCard: View {
    let title: String
    let icon: String
    let color: Color
    let url: URL?
    let action: (() -> Void)?
    
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    init(
        title: String,
        icon: String,
        color: Color,
        url: URL? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.url = url
        self.action = action
    }
    
    var body: some View {
        Button {
            if let url = url {
                NSWorkspace.shared.open(url)
            } else if let action = action {
                action()
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(isHovered ? 0.15 : 0.08))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(isHovered ? color : .secondary)
                }
                
                // Title
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isHovered ? color : .primary)
                
                Spacer()
                
                // Arrow icon (for links)
                if url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(isHovered ? color : .secondary.opacity(0.5))
                }
            }
            .padding(16)
            .background(Color.semanticSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovered ? color.opacity(0.3) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .shadow(
                color: Color.primary.opacity(isHovered ? 0.1 : 0.03),
                radius: isHovered ? 10 : 4,
                x: 0,
                y: isHovered ? 3 : 1
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withMotionAwareAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Management Key Row
struct ManagementKeyRow: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var settings = MenuBarSettingsManager.shared
    @State private var regenerateError: String?
    @State private var showRegenerateConfirmation = false
    @State private var showCopyConfirmation = false
    @State private var temporaryReveal = false
    
    private var displayKey: String {
        if settings.hideSensitiveInfo && !temporaryReveal {
            let key = viewModel.proxyManager.managementKey
            return String(repeating: "•", count: 8) + "..." + key.suffix(4)
        }
        return viewModel.proxyManager.managementKey
    }
    
    var body: some View {
        LabeledContent("settings.managementKey".localized()) {
            HStack(spacing: 8) {
                Text(displayKey)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(viewModel.proxyManager.managementKey, forType: .string)
                    showCopyConfirmation = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopyConfirmation = false
                    }
                } label: {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(showCopyConfirmation ? Color.semanticSuccess : .primary)
                        .modifier(SymbolEffectTransitionModifier())
                }
                .buttonStyle(.borderless)
                .help("action.copy".localized())
                .accessibilityLabel("action.copy".localized())

                if settings.hideSensitiveInfo {
                    Button {
                        temporaryReveal = true
                        Task {
                            try? await Task.sleep(for: .seconds(8))
                            temporaryReveal = false
                        }
                    } label: {
                        Image(systemName: temporaryReveal ? "eye.fill" : "eye")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("settings.managementKey.revealTemporary".localized(fallback: "临时显示 8 秒"))
                    .accessibilityLabel("settings.managementKey.revealTemporary".localized(fallback: "临时显示 8 秒"))
                }
                
                Button {
                    showRegenerateConfirmation = true
                } label: {
                    if viewModel.proxyManager.isRegeneratingKey {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.proxyManager.isRegeneratingKey)
                .help("settings.managementKey.regenerate".localized())
                .accessibilityLabel("settings.managementKey.regenerate".localized())
            }
        }
        .confirmationDialog(
            "settings.managementKey.regenerate.title".localized(),
            isPresented: $showRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.managementKey.regenerate.confirm".localized(), role: .destructive) {
                Task {
                    regenerateError = nil
                    do {
                        try await viewModel.proxyManager.regenerateManagementKey()
                    } catch {
                        regenerateError = error.localizedDescription
                    }
                }
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("settings.managementKey.regenerate.warning".localized())
        }
        .alert("status.error".localized(fallback: "错误"), isPresented: .init(
            get: { regenerateError != nil },
            set: { if !$0 { regenerateError = nil } }
        )) {
            Button("action.ok".localized(fallback: "确定")) { regenerateError = nil }
        } message: {
            Text(regenerateError ?? "")
        }
    }
}

// MARK: - Launch at Login Toggle

/// Reusable toggle component for Launch at Login functionality
/// Uses LaunchAtLoginManager for proper SMAppService handling
struct LaunchAtLoginToggle: View {
    private let launchManager = LaunchAtLoginManager.shared
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showLocationWarning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("settings.launchAtLogin".localized(), isOn: Binding(
                get: { launchManager.isEnabled },
                set: { newValue in
                    do {
                        try launchManager.setEnabled(newValue)
                        
                        // Show warning if app is not in /Applications when enabling
                        if newValue && !launchManager.isInValidLocation {
                            showLocationWarning = true
                        } else {
                            showLocationWarning = false
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            ))
            
            // Show location warning inline
            if showLocationWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                        .font(.caption)
                    Text("launchAtLogin.warning.notInApplications".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            }
        }
        .onAppear {
            // Refresh status when view appears to sync with System Settings
            launchManager.refreshStatus()
        }
        .alert("launchAtLogin.error.title".localized(), isPresented: $showError) {
            Button("action.ok".localized(fallback: "确定")) { showError = false }
            Button("launchAtLogin.openSystemSettings".localized()) {
                launchManager.openSystemSettings()
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Usage Display Settings Section

struct UsageDisplaySettingsSection: View {
    @State private var settings = MenuBarSettingsManager.shared
    
    private var totalUsageModeBinding: Binding<TotalUsageMode> {
        Binding(
            get: { settings.totalUsageMode },
            set: { settings.totalUsageMode = $0 }
        )
    }
    
    private var modelAggregationModeBinding: Binding<ModelAggregationMode> {
        Binding(
            get: { settings.modelAggregationMode },
            set: { settings.modelAggregationMode = $0 }
        )
    }
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.usageDisplay.totalMode.title".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: totalUsageModeBinding) {
                    ForEach(TotalUsageMode.allCases) { mode in
                        Text(mode.localizationKey.localized()).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("settings.usageDisplay.totalMode.title".localized())
                .help("settings.usageDisplay.totalMode.title".localized())
                
                Text("settings.usageDisplay.totalMode.description".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.usageDisplay.modelAggregation.title".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: modelAggregationModeBinding) {
                    ForEach(ModelAggregationMode.allCases) { mode in
                        Text(mode.localizationKey.localized()).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("settings.usageDisplay.modelAggregation.title".localized())
                .help("settings.usageDisplay.modelAggregation.title".localized())
                
                Text("settings.usageDisplay.modelAggregation.description".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Label("settings.usageDisplay.title".localized(), systemImage: "chart.bar.doc.horizontal")
        } footer: {
            Text("settings.usageDisplay.description".localized())
                .font(.caption)
        }
    }
}
