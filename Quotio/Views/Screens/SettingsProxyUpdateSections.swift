//
//  SettingsProxyUpdateSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProxyUpdateSettingsSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCheckingForUpdate = false
    @State private var isUpgrading = false
    @State private var upgradeError: String?
    @State private var showAdvancedSheet = false
    @State private var checkActionState: UpdateButtonState = .idle
    @State private var upgradeActionState: UpdateButtonState = .idle
    @State private var checkResetTask: Task<Void, Never>?
    @State private var upgradeResetTask: Task<Void, Never>?
    @State private var isCheckButtonHovered = false
    @State private var isUpgradeButtonHovered = false
    @State private var isAdvancedButtonHovered = false

    private enum UpdateButtonState: Equatable {
        case idle
        case busy
        case success
        case failure
    }

    private var updateSuccessFeedbackMilliseconds: Int {
        TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion) * 3
    }

    private var proxyManager: CLIProxyManager {
        viewModel.proxyManager
    }

    var body: some View {
        Section {
            // Current version
            LabeledContent("settings.proxyUpdate.currentVersion".localized()) {
                if let version = proxyManager.currentVersion ?? proxyManager.installedProxyVersion {
                    Text("v\(version)")
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("settings.proxyUpdate.unknown".localized())
                        .foregroundStyle(.secondary)
                }
            }
            
            // Upgrade status
            if proxyManager.upgradeAvailable, let upgrade = proxyManager.availableUpgrade {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text("settings.proxyUpdate.available".localized())
                        } icon: {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(Color.semanticSuccess)
                        }
                        
                        Text("v\(upgrade.version)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        performUpgrade(to: upgrade)
                    } label: {
                        ZStack {
                            if upgradeActionState == .busy {
                                Label("status.connecting".localized(fallback: "升级中"), systemImage: "arrow.triangle.2.circlepath")
                            } else if upgradeActionState == .success {
                                Label("status.connected".localized(fallback: "已完成"), systemImage: "checkmark.circle.fill")
                            } else if upgradeActionState == .failure {
                                Label("status.error".localized(fallback: "升级失败"), systemImage: "exclamationmark.circle.fill")
                            } else {
                                Text("action.update".localized())
                            }
                            
                            if isUpgrading {
                                SmallProgressView()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpgrading || !proxyManager.proxyStatus.running)
                    .help(upgradeHintText)
                    .accessibilityHint(upgradeHintText)
                    .scaleEffect(isUpgradeButtonHovered && !reduceMotion ? QuotioMotion.Scale.hovered : 1)
                    .motionAwareAnimation(QuotioMotion.hover, value: isUpgradeButtonHovered)
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: upgradeActionState)
                    .onHover { hovering in
                        withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                            isUpgradeButtonHovered = hovering
                        }
                    }
                }
            } else {
                HStack {
                    Label {
                        Text("settings.proxyUpdate.upToDate".localized())
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticSuccess)
                    }
                    
                    Spacer()
                    
                    Button {
                        checkForUpdate()
                    } label: {
                        ZStack {
                            if checkActionState == .busy {
                                Label("status.connecting".localized(fallback: "检查中"), systemImage: "arrow.triangle.2.circlepath")
                            } else if checkActionState == .success {
                                Label("status.connected".localized(fallback: "已检查"), systemImage: "checkmark.circle.fill")
                            } else if checkActionState == .failure {
                                Label("status.error".localized(fallback: "检查失败"), systemImage: "exclamationmark.circle.fill")
                            } else {
                                Text("settings.proxyUpdate.checkNow".localized())
                            }
                            
                            if isCheckingForUpdate {
                                SmallProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingForUpdate)
                    .help(checkHintText)
                    .accessibilityHint(checkHintText)
                    .scaleEffect(isCheckButtonHovered && !reduceMotion ? QuotioMotion.Scale.hovered : 1)
                    .motionAwareAnimation(QuotioMotion.hover, value: isCheckButtonHovered)
                    .motionAwareAnimation(QuotioMotion.contentSwap, value: checkActionState)
                    .onHover { hovering in
                        withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                            isCheckButtonHovered = hovering
                        }
                    }
                }
            }
            
            // Last checked time
            HStack {
                Text("settings.lastChecked".localized())
                Spacer()
                if let date = proxyManager.lastProxyUpdateCheckDate {
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("settings.never".localized())
                        .foregroundStyle(.secondary)
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
            
            // Proxy must be running hint (only shown when upgrade available but proxy not running)
            if proxyManager.upgradeAvailable && !proxyManager.proxyStatus.running {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.semanticInfo)
                    Text("settings.proxyUpdate.proxyMustRun".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Advanced button
            Button {
                showAdvancedSheet = true
            } label: {
                HStack {
                    Label("settings.proxyUpdate.advanced".localized(), systemImage: "gearshape.2")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(MenuRowButtonStyle(hoverColor: Color.semanticInfo.opacity(0.08), cornerRadius: 8))
            .help("settings.proxyUpdate.advanced".localized())
            .accessibilityHint("settings.proxyUpdate.advanced".localized())
            .scaleEffect(isAdvancedButtonHovered && !reduceMotion ? QuotioMotion.Scale.hovered : 1)
            .motionAwareAnimation(QuotioMotion.hover, value: isAdvancedButtonHovered)
            .onHover { hovering in
                withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                    isAdvancedButtonHovered = hovering
                }
            }
        } header: {
            Label("settings.proxyUpdate".localized(), systemImage: "shippingbox.and.arrow.backward")
        } footer: {
            Text("settings.proxyUpdate.help".localized())
                .font(.caption)
        }
        .sheet(isPresented: $showAdvancedSheet) {
            ProxyVersionManagerSheet()
                .environment(viewModel)
        }
        .onDisappear {
            checkResetTask?.cancel()
            upgradeResetTask?.cancel()
        }
    }
    
    private func checkForUpdate() {
        checkResetTask?.cancel()
        setCheckActionState(.busy)
        isCheckingForUpdate = true
        upgradeError = nil

        Task { @MainActor in
            defer {
                // Always reset loading state
                isCheckingForUpdate = false
            }

            await proxyManager.checkForUpgrade()
            guard upgradeError == nil else {
                scheduleCheckActionReset(.failure)
                return
            }
            scheduleCheckActionReset(.success)
        }
    }
    
    private func performUpgrade(to version: ProxyVersionInfo) {
        upgradeResetTask?.cancel()
        setUpgradeActionState(.busy)
        isUpgrading = true
        upgradeError = nil
        
        Task { @MainActor in
            do {
                try await proxyManager.performManagedUpgrade(to: version)
                isUpgrading = false
                scheduleUpgradeActionReset(.success)
            } catch {
                upgradeError = error.localizedDescription
                isUpgrading = false
                scheduleUpgradeActionReset(.failure)
            }
        }
    }

    private var checkHintText: String {
        switch checkActionState {
        case .busy:
            return "settings.proxyUpdate.checkNow".localized(fallback: "正在检查更新")
        case .failure:
            return "status.error".localized(fallback: "更新检查失败")
        default:
            return "settings.proxyUpdate.checkNow".localized()
        }
    }

    private var upgradeHintText: String {
        switch upgradeActionState {
        case .busy:
            return "action.update".localized(fallback: "正在升级")
        case .failure:
            return "status.error".localized(fallback: "升级失败")
        default:
            return "action.update".localized()
        }
    }

    private func scheduleCheckActionReset(_ state: UpdateButtonState) {
        checkResetTask?.cancel()
        setCheckActionState(state)
        checkResetTask = Task {
            try? await Task.sleep(for: .milliseconds(updateSuccessFeedbackMilliseconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                setCheckActionState(.idle)
            }
        }
    }

    private func scheduleUpgradeActionReset(_ state: UpdateButtonState) {
        upgradeResetTask?.cancel()
        setUpgradeActionState(state)
        upgradeResetTask = Task {
            try? await Task.sleep(for: .milliseconds(updateSuccessFeedbackMilliseconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                setUpgradeActionState(.idle)
            }
        }
    }

    private func setCheckActionState(_ state: UpdateButtonState) {
        withMotionAwareAnimation(updateButtonAnimation(from: checkActionState, to: state), reduceMotion: reduceMotion) {
            checkActionState = state
        }
    }

    private func setUpgradeActionState(_ state: UpdateButtonState) {
        withMotionAwareAnimation(updateButtonAnimation(from: upgradeActionState, to: state), reduceMotion: reduceMotion) {
            upgradeActionState = state
        }
    }

    private func updateButtonAnimation(from oldState: UpdateButtonState, to newState: UpdateButtonState) -> Animation {
        if newState == .success {
            return QuotioMotion.successEmphasis
        }
        if oldState == .failure, newState == .idle {
            return QuotioMotion.dismiss
        }
        return QuotioMotion.contentSwap
    }
}

// MARK: - Proxy Version Manager Sheet

struct ProxyVersionManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var availableReleases: [GitHubRelease] = []
    @State private var installedVersions: [InstalledProxyVersion] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var installingVersion: String?
    @State private var installError: String?
    @State private var feedbackMessage: String?
    @State private var feedbackDismissTask: Task<Void, Never>?
    
    // State for deletion warning
    @State private var showDeleteWarning = false
    @State private var pendingInstallRelease: GitHubRelease?

    private var feedbackDismissDelay: Duration {
        .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion) * 11)
    }
    @State private var versionsToDelete: [String] = []
    
    private var proxyManager: CLIProxyManager {
        viewModel.proxyManager
    }

    private enum ContentPhase: Equatable {
        case loading
        case error
        case content
    }

    private var contentPhase: ContentPhase {
        if isLoading { return .loading }
        if loadError != nil { return .error }
        return .content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.proxyUpdate.advanced.title".localized())
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("settings.proxyUpdate.advanced.description".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
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
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("settings.proxyUpdate.advanced.loading".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .quotioStateSwapTransition(reduceMotion: reduceMotion)
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(Color.semanticWarning)
                    Text("settings.proxyUpdate.advanced.fetchError".localized())
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("action.refresh".localized()) {
                        Task { await loadReleases() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .quotioStateSwapTransition(reduceMotion: reduceMotion)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Installed Versions Section
                        if !installedVersions.isEmpty {
                            sectionHeader("settings.proxyUpdate.advanced.installedVersions".localized())
                            
                            ForEach(installedVersions) { installed in
                                InstalledVersionRow(
                                    version: installed,
                                    onActivate: { activateVersion(installed.version) },
                                    onDelete: { deleteVersion(installed.version) }
                                )
                                Divider().padding(.leading, 16)
                            }
                        }
                        
                        // Available Versions Section
                        sectionHeader("settings.proxyUpdate.advanced.availableVersions".localized())
                        
                        if availableReleases.isEmpty {
                            HStack {
                                Text("settings.proxyUpdate.advanced.noReleases".localized())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ForEach(availableReleases, id: \.tagName) { release in
                                AvailableVersionRow(
                                    release: release,
                                    isInstalled: isVersionInstalled(release.versionString),
                                    isInstalling: installingVersion == release.versionString,
                                    onInstall: { installVersion(release) }
                                )
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom)
                }
                .quotioStateSwapTransition(reduceMotion: reduceMotion)
            }
            
            // Error footer
            if let error = installError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        installError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("action.dismiss".localized(fallback: "关闭错误提示"))
                    .help("action.dismiss".localized(fallback: "关闭错误提示"))
                }
                .padding()
                .background(Color.semanticWarningFill)
            }
        }
        .frame(width: 500, height: 500)
        .task {
            await loadReleases()
        }
        .alert("settings.proxyUpdate.deleteWarning.title".localized(), isPresented: $showDeleteWarning) {
            Button("action.cancel".localized(), role: .cancel) {
                pendingInstallRelease = nil
                versionsToDelete = []
            }
            Button("settings.proxyUpdate.deleteWarning.confirm".localized(), role: .destructive) {
                if let release = pendingInstallRelease {
                    performInstall(release)
                }
                pendingInstallRelease = nil
                versionsToDelete = []
            }
        } message: {
            Text(String(format: "settings.proxyUpdate.deleteWarning.message".localized(), AppConstants.maxInstalledVersions, versionsToDelete.joined(separator: ", ")))
        }
        .overlay(alignment: .top) {
            if let feedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.semanticSuccess)
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
                        .strokeBorder(Color.semanticSuccess.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.primary.opacity(0.1), radius: 8, x: 0, y: 3)
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(feedbackMessage)
            }
        }
        .motionAwareAnimation(QuotioMotion.contentSwap, value: contentPhase)
        .onDisappear {
            feedbackDismissTask?.cancel()
        }
    }
    
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.semanticSurfaceBase.opacity(0.5))
    }
    
    private func isVersionInstalled(_ version: String) -> Bool {
        installedVersions.contains { $0.version == version }
    }
    
    private func refreshInstalledVersions() {
        installedVersions = proxyManager.installedVersions
    }
    
    private func loadReleases() async {
        isLoading = true
        loadError = nil
        
        do {
            availableReleases = try await proxyManager.fetchAvailableReleases(limit: 15)
            refreshInstalledVersions()
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
    
    private func installVersion(_ release: GitHubRelease) {
        guard proxyManager.versionInfo(from: release) != nil else {
            installError = "settings.proxyUpdate.advanced.noCompatibleBinary".localized(fallback: "当前系统没有可用的二进制版本")
            return
        }
        
        // Check if installing will delete old versions
        let toDelete = proxyManager.storageManager.versionsToBeDeleted(keepLast: AppConstants.maxInstalledVersions)
        if !toDelete.isEmpty {
            versionsToDelete = toDelete
            pendingInstallRelease = release
            showDeleteWarning = true
            return
        }
        
        performInstall(release)
    }
    
    private func performInstall(_ release: GitHubRelease) {
        guard let versionInfo = proxyManager.versionInfo(from: release) else {
            installError = "settings.proxyUpdate.advanced.noCompatibleBinary".localized(fallback: "当前系统没有可用的二进制版本")
            return
        }
        
        installingVersion = release.versionString
        installError = nil
        
        Task { @MainActor in
            do {
                try await proxyManager.performManagedUpgrade(to: versionInfo)
                installingVersion = nil
                refreshInstalledVersions()
                showFeedback(
                    "settings.proxyUpdate.advanced.installSuccess".localized(fallback: "版本已安装") + ": v" + release.versionString
                )
            } catch {
                installError = error.localizedDescription
                installingVersion = nil
            }
        }
    }
    
    private func activateVersion(_ version: String) {
        installError = nil
        Task { @MainActor in
            do {
                let wasRunning = proxyManager.proxyStatus.running
                if wasRunning {
                    proxyManager.stop()
                }
                try proxyManager.storageManager.setCurrentVersion(version)
                if wasRunning {
                    try await proxyManager.start()
                }
                refreshInstalledVersions()
                showFeedback(
                    "settings.proxyUpdate.advanced.activateSuccess".localized(fallback: "版本已激活") + ": v" + version
                )
            } catch {
                installError = error.localizedDescription
            }
        }
    }
    
    private func deleteVersion(_ version: String) {
        installError = nil
        do {
            try proxyManager.storageManager.deleteVersion(version)
            refreshInstalledVersions()
            showFeedback(
                "settings.proxyUpdate.advanced.deleteSuccess".localized(fallback: "版本已删除") + ": v" + version
            )
        } catch {
            installError = error.localizedDescription
        }
    }

    private func showFeedback(_ message: String) {
        feedbackDismissTask?.cancel()
        withMotionAwareAnimation(QuotioMotion.appear, reduceMotion: reduceMotion) {
            feedbackMessage = message
        }

        feedbackDismissTask = Task {
            try? await Task.sleep(for: feedbackDismissDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withMotionAwareAnimation(QuotioMotion.dismiss, reduceMotion: reduceMotion) {
                    feedbackMessage = nil
                }
            }
        }
    }
}

// MARK: - Installed Version Row

private struct InstalledVersionRow: View {
    let version: InstalledProxyVersion
    let onActivate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Version info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("v\(version.version)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    if version.isCurrent {
                        Text("settings.proxyUpdate.advanced.current".localized())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.semanticOnAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.semanticSuccess)
                            .clipShape(Capsule())
                    }
                }
                
                Text(version.installedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Actions
            if !version.isCurrent {
                Button("settings.proxyUpdate.advanced.activate".localized()) {
                    onActivate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(Color.semanticDanger)
                .accessibilityLabel("action.delete".localized())
                .help("action.delete".localized())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Available Version Row

private struct AvailableVersionRow: View {
    let release: GitHubRelease
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    
    // Cached DateFormatters to avoid repeated allocations (performance fix)
    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 12) {
            // Version info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("v\(release.versionString)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    if release.prerelease {
                        Text("settings.proxyUpdate.advanced.prerelease".localized())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.semanticWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.semanticWarning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    if isInstalled {
                        Text("settings.proxyUpdate.advanced.installed".localized())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                
                if let publishedAt = release.publishedAt {
                    Text(formatDate(publishedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Install button
            if !isInstalled {
                Button {
                    onInstall()
                } label: {
                    if isInstalling {
                        SmallProgressView()
                    } else {
                        Text("settings.proxyUpdate.advanced.install".localized())
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isInstalling)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func formatDate(_ isoString: String) -> String {
        // Try with fractional seconds first
        if let date = Self.isoFormatterWithFractional.date(from: isoString) {
            return Self.displayFormatter.string(from: date)
        }
        
        // Try without fractional seconds
        if let date = Self.isoFormatterStandard.date(from: isoString) {
            return Self.displayFormatter.string(from: date)
        }
        
        return isoString
    }
}

// MARK: - Menu Bar Settings Section
