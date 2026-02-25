//
//  QuotioApp.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import AppKit
import SwiftUI
import ServiceManagement
#if canImport(Sparkle)
import Sparkle
#endif

private enum RuntimeMode {
    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil {
            return true
        }
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains { $0.localizedCaseInsensitiveContains("xctest") }
    }

    static var isUITestHarnessEnabled: Bool {
        ProcessInfo.processInfo.environment["QUOTIO_UI_TEST_MODE"] == "1"
    }
}

// MARK: - App Bootstrap (Singleton for headless initialization)

/// Manages app-wide initialization that must happen regardless of window visibility.
/// This ensures the app works correctly when launched at login without opening a window.
@MainActor
final class AppBootstrap {
    static let shared = AppBootstrap()

    let viewModel = QuotaViewModel()
    let logsViewModel = LogsViewModel()

    private(set) var hasInitialized = false
    private(set) var needsOnboarding = false

    private let modeManager = OperatingModeManager.shared
    private let appearanceManager = AppearanceManager.shared
    private let statusBarManager = StatusBarManager.shared
    private let menuBarSettings = MenuBarSettingsManager.shared

    private init() {}

    /// Initialize core app services. Safe to call multiple times - only runs once.
    /// Called from AppDelegate.applicationDidFinishLaunching for headless launch support.
    func initializeIfNeeded() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Hosted unit tests should not execute app bootstrap side effects.
        if RuntimeMode.isRunningTests {
            return
        }

        appearanceManager.applyAppearance()

        // Check if onboarding is needed - if so, defer full initialization until after onboarding
        if !modeManager.hasCompletedOnboarding {
            needsOnboarding = true
            return
        }

        await performFullInitialization()
    }

    /// Called after onboarding completes to finish initialization
    func completeOnboarding() async {
        needsOnboarding = false
        await performFullInitialization()
    }

    private func performFullInitialization() async {
        // Scan auth files immediately (fast filesystem scan)
        // This allows menu bar to show providers before quota API calls complete
        await viewModel.loadDirectAuthFiles()

        // Setup menu bar immediately so user can open it while data loads
        statusBarManager.setViewModel(viewModel)
        updateStatusBar()

        // Listen for quota data changes to update menu bar even when window is closed
        NotificationCenter.default.addObserver(
            forName: QuotaViewModel.quotaDataDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusBar()
                StatusBarManager.shared.rebuildMenuInPlace()
            }
        }

        // Load data in background (includes proxy auto-start if enabled)
        await viewModel.initialize()

        #if canImport(Sparkle)
        UpdaterService.shared.checkForUpdatesInBackground()
        #endif
    }

    func updateStatusBar() {
        // Menu bar should show quota data regardless of proxy status
        // The quota is fetched directly and doesn't need proxy
        let hasQuotaData = !viewModel.providerQuotas.isEmpty

        statusBarManager.updateStatusBar(
            items: quotaItems,
            colorMode: menuBarSettings.colorMode,
            isRunning: hasQuotaData,
            showMenuBarIcon: menuBarSettings.showMenuBarIcon,
            showQuota: menuBarSettings.showQuotaInMenuBar
        )
    }

    private var quotaItems: [MenuBarQuotaDisplayItem] {
        guard menuBarSettings.showQuotaInMenuBar else { return [] }

        var items: [MenuBarQuotaDisplayItem] = []

        for selectedItem in menuBarSettings.selectedItems {
            guard let provider = selectedItem.aiProvider else { continue }

            var displayPercent: Double = -1
            var isForbidden = false

            if let accountQuotas = viewModel.providerQuotas[provider],
               let quotaData = resolveQuotaData(
                   for: selectedItem,
                   provider: provider,
                   accountQuotas: accountQuotas
               ) {
                isForbidden = quotaData.isForbidden
                if !quotaData.models.isEmpty {
                    let models = quotaData.models.map { (name: $0.name, percentage: $0.percentage) }
                    displayPercent = menuBarSettings.totalUsagePercent(models: models)
                }
            }

            items.append(MenuBarQuotaDisplayItem(
                id: selectedItem.id,
                providerSymbol: provider.menuBarSymbol,
                accountShort: selectedItem.accountKey,
                percentage: displayPercent,
                provider: provider,
                isForbidden: isForbidden
            ))
        }

        return items
    }

    private func resolveQuotaData(
        for selectedItem: MenuBarQuotaItem,
        provider: AIProvider,
        accountQuotas: [String: ProviderQuotaData]
    ) -> ProviderQuotaData? {
        if let quotaData = accountQuotas[selectedItem.accountKey] {
            return quotaData
        }

        let cleanKey = selectedItem.accountKey.replacingOccurrences(of: ".json", with: "")
        if let quotaData = accountQuotas[cleanKey] {
            return quotaData
        }

        guard provider == .codex else { return nil }
        let normalizedSelected = normalizedCodexKey(cleanKey)
        return accountQuotas.first { normalizedCodexKey($0.key) == normalizedSelected }?.value
    }

    private func normalizedCodexKey(_ key: String) -> String {
        let cleanKey = key.replacingOccurrences(of: ".json", with: "")
        if let email = extractEmail(from: cleanKey) {
            return email.lowercased()
        }
        return cleanKey.lowercased()
    }

    private func extractEmail(from text: String) -> String? {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        guard let range = text.range(of: pattern, options: options) else { return nil }
        return String(text[range])
    }
}

@main
struct QuotioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Use shared bootstrap instance for viewModel
    private var bootstrap: AppBootstrap { AppBootstrap.shared }
    @State private var logsViewModel = LogsViewModel()
    @State private var menuBarSettings = MenuBarSettingsManager.shared
    @State private var statusBarManager = StatusBarManager.shared
    @State private var modeManager = OperatingModeManager.shared
    @State private var appearanceManager = AppearanceManager.shared
    @State private var languageManager = LanguageManager.shared
    @State private var showOnboarding = false
    @Environment(\.openWindow) private var openWindow

    private var viewModel: QuotaViewModel { bootstrap.viewModel }

    var body: some Scene {
        Window("Quotio", id: "main") {
            Group {
                if RuntimeMode.isUITestHarnessEnabled {
                    UITestHarnessView()
                } else {
                    ContentView()
                        .id(languageManager.currentLanguage) // Force re-render on language change
                        .environment(viewModel)
                        .environment(logsViewModel)
                        .environment(\.locale, languageManager.locale)
                        .task {
                            // Initialize via bootstrap (idempotent - safe to call multiple times)
                            // This handles the case where window opens before AppDelegate finishes
                            await bootstrap.initializeIfNeeded()

                            // Show onboarding if needed
                            if bootstrap.needsOnboarding {
                                showOnboarding = true
                            }
                        }
                        .onChange(of: viewModel.proxyManager.proxyStatus.running) {
                            bootstrap.updateStatusBar()
                        }
                        .onChange(of: viewModel.isLoadingQuotas) {
                            bootstrap.updateStatusBar()
                            // Rebuild menu when loading state changes so loader updates
                            statusBarManager.rebuildMenuInPlace()
                        }
                        .onChange(of: languageManager.currentLanguage) { _, _ in
                            // Rebuild menu bar when language changes
                            statusBarManager.rebuildMenuInPlace()
                        }
                        .onChange(of: menuBarSettings.showQuotaInMenuBar) {
                            bootstrap.updateStatusBar()
                        }
                        .onChange(of: menuBarSettings.showMenuBarIcon) {
                            bootstrap.updateStatusBar()
                        }
                        .onChange(of: menuBarSettings.selectedItems) {
                            bootstrap.updateStatusBar()
                        }
                        .onChange(of: menuBarSettings.colorMode) {
                            bootstrap.updateStatusBar()
                        }
                        .onChange(of: menuBarSettings.totalUsageMode) {
                            bootstrap.updateStatusBar()
                            statusBarManager.rebuildMenuInPlace()
                        }
                        .onChange(of: menuBarSettings.modelAggregationMode) {
                            bootstrap.updateStatusBar()
                            statusBarManager.rebuildMenuInPlace()
                        }
                        .onChange(of: modeManager.currentMode) {
                            bootstrap.updateStatusBar()
                        }
                        .onChange(of: viewModel.providerQuotas.count) {
                            bootstrap.updateStatusBar()
                            statusBarManager.rebuildMenuInPlace()
                        }
                        .onChange(of: viewModel.directAuthFiles.count) {
                            bootstrap.updateStatusBar()
                            statusBarManager.rebuildMenuInPlace()
                        }
                        .sheet(isPresented: $showOnboarding) {
                            OnboardingFlow {
                                Task {
                                    await bootstrap.completeOnboarding()
                                }
                            }
                        }
                    }
                }
            }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }

            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdaterService.shared.checkForUpdates()
                }
                .disabled(!UpdaterService.shared.canCheckForUpdates)
            }
            #endif
        }
    }
}

private struct UITestHarnessView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("ui.test.harness.title".localized(fallback: "Quotio UI Test Harness"))
                .font(.title3.weight(.semibold))
            Text("ui.test.harness.ready".localized(fallback: "UI 测试就绪"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("ui-test-harness-root")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private nonisolated(unsafe) var windowWillCloseObserver: NSObjectProtocol?
    private nonisolated(unsafe) var windowDidBecomeKeyObserver: NSObjectProtocol?
    private var skipTerminationCleanup = false
    private static let coreEventClass = fourCharCode("aevt")
    private static let quitEventID = fourCharCode("quit")
    private static let senderPIDAttribute = fourCharCode("spid")
    private static let addressAttribute = fourCharCode("addr")
    private static let originalAddressAttribute = fourCharCode("from")
    private nonisolated static let terminationTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if RuntimeMode.isRunningTests {
            return
        }

        appendTerminationAudit("launch selfPID=\(ProcessInfo.processInfo.processIdentifier)")

        // Multiple Quotio instances race on shared proxy ports/config and can trigger restart loops.
        guard enforceSingleInstance() else {
            return
        }

        // Move orphan cleanup off main thread to avoid blocking app launch
        DispatchQueue.global(qos: .utility).async {
            TunnelManager.cleanupOrphans()
        }

        UserDefaults.standard.register(defaults: [
            "useBridgeMode": true,
            "showInDock": true,
            "totalUsageMode": TotalUsageMode.sessionOnly.rawValue,
            "modelAggregationMode": ModelAggregationMode.lowest.rawValue
        ])

        // Apply initial dock visibility based on saved preference
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        // CRITICAL: Initialize app services immediately on launch.
        // This ensures proxy auto-start works even when launched at login
        // without opening a window (e.g., when showInDock=false).
        // The bootstrap.initializeIfNeeded() is idempotent and safe to call
        // multiple times - the window's .task will also call it but it's a no-op
        // if already initialized.
        Task { @MainActor in
            await AppBootstrap.shared.initializeIfNeeded()

            // Start background polling for CLIProxyAPI updates (every 5 minutes)
            // Uses Atom feed with ETag caching for efficiency
            AtomFeedUpdateService.shared.startPolling {
                CLIProxyManager.shared.currentVersion ?? CLIProxyManager.shared.installedProxyVersion
            }
        }

        windowWillCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWindowWillClose()
            }
        }

        windowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWindowDidBecomeKey()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logTerminationRequestSource()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When user clicks dock icon or menubar "Open Quotio" and no visible windows
        if !flag {
            // Find and show the main window
            for window in sender.windows {
                if window.title == "Quotio" {
                    // Restore minimized window first
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }

    private func enforceSingleInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        guard let existingInstance = otherInstances.sorted(by: { $0.processIdentifier < $1.processIdentifier }).first else {
            return true
        }

        _ = existingInstance.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        skipTerminationCleanup = true
        appendTerminationAudit(
            "duplicate_detected selfPID=\(currentPID), existingPID=\(existingInstance.processIdentifier), action=terminate_self"
        )
        Log.warning("[AppDelegate] Duplicate Quotio instance detected. Activating PID \(existingInstance.processIdentifier) and terminating PID \(currentPID).")
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        return false
    }

    private func logTerminationRequestSource() {
        var details = ["selfPID=\(ProcessInfo.processInfo.processIdentifier)"]

        if let event = NSAppleEventManager.shared().currentAppleEvent {
            let eventClass = event.eventClass
            let eventID = event.eventID
            details.append("eventClass=\(Self.fourCharCodeString(eventClass))")
            details.append("eventID=\(Self.fourCharCodeString(eventID))")

            if eventClass == Self.coreEventClass && eventID == Self.quitEventID {
                details.append("source=quit_apple_event")
            } else {
                details.append("source=apple_event")
            }

            if let senderPID = senderPID(from: event), senderPID > 0 {
                details.append("senderPID=\(senderPID)")
                if let senderApp = NSRunningApplication(processIdentifier: senderPID) {
                    if let senderName = senderApp.localizedName {
                        details.append("senderProcessName=\(senderName)")
                    }
                    if let senderBundleID = senderApp.bundleIdentifier {
                        details.append("senderBundleID=\(senderBundleID)")
                    }
                }
                if let snapshot = processSnapshot(pid: senderPID) {
                    details.append("senderCmd=\(snapshot.command)")
                    if snapshot.parentPID > 0, let parent = processSnapshot(pid: snapshot.parentPID) {
                        details.append("senderParentPID=\(snapshot.parentPID)")
                        details.append("senderParentCmd=\(parent.command)")
                        if parent.parentPID > 0, let grandParent = processSnapshot(pid: parent.parentPID) {
                            details.append("senderGrandParentPID=\(parent.parentPID)")
                            details.append("senderGrandParentCmd=\(grandParent.command)")
                        }
                    }
                }
            } else {
                details.append("senderPID=unknown")
            }

            let addressInfo = appleEventAddressSummary(from: event)
            if !addressInfo.isEmpty {
                details.append(addressInfo)
            }
        } else {
            details.append("source=non_apple_event")
        }

        let summary = details.joined(separator: ", ")
        appendTerminationAudit("termination_requested \(summary)")
        Log.warning("[AppDelegate] Termination requested (\(summary))")
    }

    private func appendTerminationAudit(_ message: String) {
        Self.appendTerminationAuditLine(message)
    }

    private nonisolated static func appendTerminationAuditLine(_ message: String) {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let logURL = supportDirectory
            .appendingPathComponent("Quotio", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("quotio-termination.log", isDirectory: false)
        let line = "[\(Self.terminationTimestampFormatter.string(from: Date()))] \(message)\n"

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            Log.warning("[AppDelegate] Failed to append termination audit: \(error.localizedDescription)")
        }
    }

    private func senderPID(from event: NSAppleEventDescriptor) -> Int32? {
        guard let descriptor = event.attributeDescriptor(forKeyword: Self.senderPIDAttribute) else {
            return nil
        }
        let value = descriptor.int32Value
        return value > 0 ? value : nil
    }

    private func appleEventAddressSummary(from event: NSAppleEventDescriptor) -> String {
        var segments: [String] = []
        if let address = event.attributeDescriptor(forKeyword: Self.addressAttribute) {
            segments.append("address=\(Self.compactDescriptor(address))")
        }
        if let originalAddress = event.attributeDescriptor(forKeyword: Self.originalAddressAttribute) {
            segments.append("from=\(Self.compactDescriptor(originalAddress))")
        }
        return segments.joined(separator: ", ")
    }

    private func processSnapshot(pid: Int32) -> (parentPID: Int32, command: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "pid=,ppid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty else {
                return nil
            }
            let fields = line.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace
            ).map(String.init)
            guard fields.count >= 3,
                  let parentPID = Int32(fields[1]) else {
                return nil
            }
            return (parentPID: parentPID, command: fields[2])
        } catch {
            return nil
        }
    }

    private static func compactDescriptor(_ descriptor: NSAppleEventDescriptor) -> String {
        let raw = descriptor.stringValue ?? descriptor.description
        return raw.count > 180 ? String(raw.prefix(180)) + "..." : raw
    }

    private static func fourCharCode(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCharCodeString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let printable = bytes.allSatisfy { 32...126 ~= $0 }
        if printable {
            return bytes.map { String(UnicodeScalar($0)) }.joined()
        }
        return String(format: "0x%08X", code)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if RuntimeMode.isRunningTests {
            return
        }

        if skipTerminationCleanup {
            appendTerminationAudit("will_terminate selfPID=\(ProcessInfo.processInfo.processIdentifier), skipCleanup=true")
            return
        }

        appendTerminationAudit("will_terminate selfPID=\(ProcessInfo.processInfo.processIdentifier), skipCleanup=false")
        AppLifecycleState.isTerminating = true

        // Stop background polling
        AtomFeedUpdateService.shared.stopPolling()

        // Keep CLIProxyAPI alive when Quotio exits.
        // Proxy lifecycle is controlled explicitly by user actions in-app.

        Task.detached(priority: .utility) {
            let didStopGracefully = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await TunnelManager.shared.stopTunnel()
                    return true
                }

                group.addTask {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    return false
                }

                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }

            if didStopGracefully {
                Self.appendTerminationAuditLine("will_terminate_cleanup timeout=false")
            } else {
                TunnelManager.cleanupOrphans()
                Log.warning("[AppDelegate] Tunnel cleanup timed out, forced orphan cleanup")
                Self.appendTerminationAuditLine("will_terminate_cleanup timeout=true")
            }
        }
    }

    private func handleWindowDidBecomeKey() {
        // Do nothing - activation policy is managed by showInDock setting only
    }

    private func handleWindowWillClose() {
        // Do nothing - activation policy is managed by showInDock setting only
        // When showInDock = true, dock icon stays visible even when window is closed
        // When showInDock = false, dock icon is never visible
    }
    
    deinit {
        if let observer = windowWillCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowDidBecomeKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct ContentView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @AppStorage("loggingToFile") private var loggingToFile = true
    @State private var modeManager = OperatingModeManager.shared
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiMetrics = UIBaselineMetricsTracker.shared
    
    var body: some View {
        @Bindable var vm = viewModel
        
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $vm.currentPage) {
                    Section("nav.section.overview".localized(fallback: "概览")) {
                        Label("nav.dashboard".localized(), systemImage: "gauge.with.dots.needle.33percent")
                            .tag(NavigationPage.dashboard)
                        
                        Label("nav.quota".localized(), systemImage: "chart.bar.fill")
                            .tag(NavigationPage.quota)
                    }

                    Section("nav.section.resources".localized(fallback: "资源")) {
                        Label(modeManager.isMonitorMode ? "nav.accounts".localized() : "nav.providers".localized(), 
                              systemImage: "person.2.badge.key")
                            .tag(NavigationPage.providers)
                    }

                    if modeManager.isProxyMode {
                        Section("nav.section.operations".localized(fallback: "运行与观测")) {
                            HStack(spacing: 6) {
                                Label("nav.fallback".localized(), systemImage: "arrow.triangle.branch")
                                ExperimentalBadge()
                            }
                            .tag(NavigationPage.fallback)

                            HStack(spacing: 6) {
                                Label("nav.reviewQueue".localized(fallback: "Review Queue"), systemImage: "checklist")
                                ExperimentalBadge()
                            }
                            .tag(NavigationPage.reviewQueue)

                            if modeManager.currentMode.supportsAgentConfig {
                                Label("nav.agents".localized(), systemImage: "terminal")
                                    .tag(NavigationPage.agents)
                            }

                            Label("nav.apiKeys".localized(), systemImage: "key.horizontal")
                                .tag(NavigationPage.apiKeys)

                            if modeManager.isLocalProxyMode && loggingToFile {
                                Label("nav.logs".localized(), systemImage: "doc.text")
                                    .tag(NavigationPage.logs)
                            }

                            Label("nav.usageStats".localized(fallback: "使用统计"), systemImage: "chart.line.uptrend.xyaxis")
                                .tag(NavigationPage.usageStats)
                        }
                    }

                    Section("nav.section.system".localized(fallback: "系统")) {
                        Label("nav.settings".localized(), systemImage: "gearshape")
                            .tag(NavigationPage.settings)
                        
                        Label("nav.about".localized(), systemImage: "info.circle")
                            .tag(NavigationPage.about)
                    }
                }
                .environment(\.defaultMinListRowHeight, uiExperience.recommendedMinimumRowHeight)
                
                // Control section at bottom - current mode badge + status
                VStack(spacing: 0) {
                    Divider()
                    
                    // Current Mode Badge (replaces ModeSwitcherRow)
                    CurrentModeBadge()
                        .padding(.horizontal, uiExperience.informationDensity == .compact ? 12 : 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    
                    // Status row - different per mode
                    Group {
                        if modeManager.isLocalProxyMode {
                            ProxyStatusRow(viewModel: viewModel)
                        } else if modeManager.isRemoteProxyMode {
                            RemoteStatusRow()
                        } else {
                            QuotaRefreshStatusRow(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, uiExperience.informationDensity == .compact ? 12 : 16)
                    .padding(.bottom, 10)
                }
                .background(.regularMaterial)
            }
            .navigationTitle("Quotio")
            .onAppear {
                uiMetrics.mark(
                    "content.sidebar.appear",
                    metadata: "mode=\(modeManager.currentMode.rawValue),enhancedUI=\(featureFlags.enhancedUILayout)"
                )
            }
            .onChange(of: vm.currentPage) { _, newPage in
                uiMetrics.mark("navigation.page_opened", metadata: newPage.rawValue)
            }
            .toolbar {
                ToolbarItem {
                    if modeManager.isLocalProxyMode {
                        // Local proxy mode: proxy controls
                        if viewModel.proxyManager.isStarting {
                            SmallProgressView()
                        } else {
                            Button {
                                Task { await viewModel.toggleProxy() }
                            } label: {
                                Image(systemName: viewModel.proxyManager.proxyStatus.running ? "stop.fill" : "play.fill")
                            }
                            .help(viewModel.proxyManager.proxyStatus.running ? "action.stopProxy".localized() : "action.startProxy".localized())
                            .accessibilityLabel(viewModel.proxyManager.proxyStatus.running ? "action.stopProxy".localized() : "action.startProxy".localized())
                        }
                    } else {
                        // Monitor or remote mode: refresh button
                        Button {
                            Task { await viewModel.refreshQuotasDirectly() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("action.refreshQuota".localized())
                        .accessibilityLabel("action.refreshQuota".localized())
                        .disabled(viewModel.isLoadingQuotas)
                    }
                }
            }
        } detail: {
            switch viewModel.currentPage {
            case .dashboard:
                DashboardScreen()
            case .quota:
                QuotaScreen()
            case .providers:
                ProvidersScreen()
            case .fallback:
                FallbackScreen()
            case .reviewQueue:
                ReviewQueueScreen()
            case .agents:
                AgentSetupScreen()
            case .apiKeys:
                APIKeysScreen()
            case .usageStats:
                UsageStatsScreen()
            case .logs:
                LogsScreen()
            case .settings:
                SettingsScreen()
            case .about:
                AboutScreen()
            }
        }
    }
}

// MARK: - Sidebar Status Rows

/// Remote connection status row for Remote Proxy Mode
struct RemoteStatusRow: View {
    @State private var modeManager = OperatingModeManager.shared
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
            
            Spacer()
            
            if let config = modeManager.remoteConfig {
                Text(config.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    private var statusColor: Color {
        switch modeManager.connectionStatus {
        case .connected: return Color.semanticSuccess
        case .connecting: return Color.semanticWarning
        case .disconnected: return .secondary
        case .error: return Color.semanticDanger
        }
    }
    
    private var statusText: String {
        switch modeManager.connectionStatus {
        case .connected: return "status.connected".localized()
        case .connecting: return "status.connecting".localized()
        case .disconnected: return "status.disconnected".localized()
        case .error: return "status.error".localized()
        }
    }
}

/// Proxy status row for Local Proxy Mode
struct ProxyStatusRow: View {
    let viewModel: QuotaViewModel
    
    var body: some View {
        HStack {
            if viewModel.proxyManager.isStarting {
                SmallProgressView(size: 8)
            } else {
                Circle()
                    .fill(viewModel.proxyManager.proxyStatus.running ? Color.semanticSuccess : .secondary)
                    .frame(width: 8, height: 8)
            }
            
            if viewModel.proxyManager.isStarting {
                Text("status.starting".localized())
                    .font(.caption)
            } else {
                Text(viewModel.proxyManager.proxyStatus.running ? "status.running".localized() : "status.stopped".localized())
                    .font(.caption)
            }
            
            Spacer()
            
            Text(":" + String(viewModel.proxyManager.port))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Quota refresh status row for Quota-Only Mode
struct QuotaRefreshStatusRow: View {
    let viewModel: QuotaViewModel
    
    var body: some View {
        HStack {
            if viewModel.isLoadingQuotas {
                SmallProgressView(size: 8)
                Text("status.refreshing".localized())
                    .font(.caption)
            } else {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if let lastRefresh = viewModel.lastQuotaRefreshTime {
                    HStack(spacing: 4) {
                        Text("status.updatedAgo".localized(fallback: "更新于"))
                        Text(lastRefresh, style: .relative)
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("status.notRefreshed".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
}
