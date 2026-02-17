//
//  SettingsProxyUpdateSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProxyUpdateSettingsSection: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var isCheckingForUpdate = false
    @State private var isUpgrading = false
    @State private var upgradeError: String?
    @State private var showAdvancedSheet = false

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
                            Text("action.update".localized())
                                .opacity(isUpgrading ? 0 : 1)
                            
                            if isUpgrading {
                                SmallProgressView()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
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
                    .disabled(isCheckingForUpdate)
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
            .buttonStyle(.plain)
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

// MARK: - Proxy Version Manager Sheet

struct ProxyVersionManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QuotaViewModel.self) private var viewModel
    
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
    @State private var versionsToDelete: [String] = []
    
    private var proxyManager: CLIProxyManager {
        viewModel.proxyManager
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
