//
//  QuotioApp.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import SwiftUI
import ServiceManagement
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct QuotioApp: App {
    @State private var viewModel = QuotaViewModel()
    @State private var menuBarSettings = MenuBarSettingsManager.shared
    @State private var statusBarManager = StatusBarManager.shared
    @AppStorage("autoStartProxy") private var autoStartProxy = false
    @Environment(\.openWindow) private var openWindow
    
    #if canImport(Sparkle)
    private let updaterService = UpdaterService.shared
    #endif
    
    private var quotaItems: [MenuBarQuotaDisplayItem] {
        guard menuBarSettings.showQuotaInMenuBar else { return [] }
        guard viewModel.proxyManager.proxyStatus.running else { return [] }
        
        var items: [MenuBarQuotaDisplayItem] = []
        
        for selectedItem in menuBarSettings.selectedItems.prefix(3) {
            guard let provider = selectedItem.aiProvider else { continue }
            
            if let accountQuotas = viewModel.providerQuotas[provider],
               let quotaData = accountQuotas[selectedItem.accountKey],
               !quotaData.models.isEmpty {
                let lowestPercent = quotaData.models.map(\.percentage).min() ?? 0
                items.append(MenuBarQuotaDisplayItem(
                    id: selectedItem.id,
                    providerSymbol: provider.menuBarSymbol,
                    accountShort: selectedItem.accountKey,
                    percentage: lowestPercent,
                    provider: provider
                ))
            } else {
                items.append(MenuBarQuotaDisplayItem(
                    id: selectedItem.id,
                    providerSymbol: provider.menuBarSymbol,
                    accountShort: selectedItem.accountKey,
                    percentage: -1,
                    provider: provider
                ))
            }
        }
        
        return items
    }
    
    private func updateStatusBar() {
        statusBarManager.updateStatusBar(
            items: quotaItems,
            colorMode: menuBarSettings.colorMode,
            isRunning: viewModel.proxyManager.proxyStatus.running,
            showQuota: menuBarSettings.showQuotaInMenuBar,
            menuContentProvider: {
                AnyView(
                    MenuBarView()
                        .environment(viewModel)
                )
            }
        )
    }
    
    var body: some Scene {
        Window("Quotio", id: "main") {
            ContentView()
                .environment(viewModel)
                .task {
                    if autoStartProxy && viewModel.proxyManager.isBinaryInstalled {
                        await viewModel.startProxy()
                    }
                    #if canImport(Sparkle)
                    updaterService.checkForUpdatesInBackground()
                    #endif
                    
                    updateStatusBar()
                }
                .onChange(of: viewModel.proxyManager.proxyStatus.running) {
                    updateStatusBar()
                }
                .onChange(of: viewModel.isLoadingQuotas) {
                    updateStatusBar()
                }
                .onChange(of: menuBarSettings.showQuotaInMenuBar) {
                    updateStatusBar()
                }
                .onChange(of: menuBarSettings.selectedItems) {
                    updateStatusBar()
                }
                .onChange(of: menuBarSettings.colorMode) {
                    updateStatusBar()
                }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.canCheckForUpdates)
            }
            #endif
        }
    }
}

struct ContentView: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @AppStorage("loggingToFile") private var loggingToFile = true
    
    var body: some View {
        @Bindable var vm = viewModel
        
        NavigationSplitView {
            List(selection: $vm.currentPage) {
                Section {
                    Label("nav.dashboard".localized(), systemImage: "gauge.with.dots.needle.33percent")
                        .tag(NavigationPage.dashboard)
                    
                    Label("nav.quota".localized(), systemImage: "chart.bar.fill")
                        .tag(NavigationPage.quota)
                    
                    Label("nav.providers".localized(), systemImage: "person.2.badge.key")
                        .tag(NavigationPage.providers)
                    
                    Label("nav.agents".localized(), systemImage: "terminal")
                        .tag(NavigationPage.agents)
                    
                    Label("nav.apiKeys".localized(), systemImage: "key.horizontal")
                        .tag(NavigationPage.apiKeys)
                    
                    if loggingToFile {
                        Label("nav.logs".localized(), systemImage: "doc.text")
                            .tag(NavigationPage.logs)
                    }
                    
                    Label("nav.settings".localized(), systemImage: "gearshape")
                        .tag(NavigationPage.settings)
                    
                    Label("nav.about".localized(), systemImage: "info.circle")
                        .tag(NavigationPage.about)
                }
                
                Section {
                    HStack {
                        Circle()
                            .fill(viewModel.proxyManager.proxyStatus.running ? .green : .gray)
                            .frame(width: 8, height: 8)
                        
                        Text(viewModel.proxyManager.proxyStatus.running ? "status.running".localized() : "status.stopped".localized())
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(":\(viewModel.proxyManager.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Quotio")
            .toolbar {
                ToolbarItem {
                    if viewModel.proxyManager.isStarting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await viewModel.toggleProxy() }
                        } label: {
                            Image(systemName: viewModel.proxyManager.proxyStatus.running ? "stop.fill" : "play.fill")
                        }
                        .help(viewModel.proxyManager.proxyStatus.running ? "action.stopProxy".localized() : "action.startProxy".localized())
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
            case .agents:
                AgentSetupScreen()
            case .apiKeys:
                APIKeysScreen()
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
