//
//  DashboardScreenRemoteModeSection.swift
//  Quotio
//

import SwiftUI

extension DashboardScreen {
    // MARK: - Remote Mode Content
    
    var remoteModeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Remote connection status banner
            remoteConnectionStatusBanner
            
            // Show content based on connection status
            switch modeManager.connectionStatus {
            case .connected:
                // Connected - show full dashboard similar to local mode
                kpiSection
                operationsCenterSection
                providerSection
                remoteEndpointSection
            case .connecting:
                // Connecting - show loading state
                remoteConnectingView
            case .disconnected, .error:
                // Not connected - show reconnect prompt
                remoteDisconnectedView
            }
        }
    }
    
    private var remoteConnectionStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(connectionStatusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("dashboard.remoteMode".localized())
                    .font(.headline)
                
                if let config = modeManager.remoteConfig {
                    Text(config.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            connectionStatusBadge
        }
        .padding()
        .background(connectionStatusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var connectionStatusColor: Color {
        switch modeManager.connectionStatus {
        case .connected: return Color.semanticSuccess
        case .connecting: return Color.semanticWarning
        case .disconnected: return .secondary
        case .error: return Color.semanticDanger
        }
    }
    
    private var connectionStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 8, height: 8)
            
            Text(connectionStatusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(connectionStatusColor.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var connectionStatusText: String {
        switch modeManager.connectionStatus {
        case .connected: return "status.connected".localized()
        case .connecting: return "status.connecting".localized()
        case .disconnected: return "status.disconnected".localized()
        case .error: return "status.error".localized()
        }
    }
    
    private var remoteConnectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("dashboard.connectingToRemote".localized())
                .font(.headline)
            
            if let config = modeManager.remoteConfig {
                Text(config.endpointURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var remoteDisconnectedView: some View {
        ContentUnavailableView {
            Label("dashboard.remoteDisconnected".localized(), systemImage: "network.slash")
        } description: {
            if case .error(let message) = modeManager.connectionStatus {
                Text(message)
            } else {
                Text("dashboard.remoteDisconnectedDesc".localized())
            }
        } actions: {
            Button {
                Task {
                    await viewModel.reconnectRemote()
                }
            } label: {
                Label("action.reconnect".localized(), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var remoteEndpointSection: some View {
        GroupBox {
            HStack {
                if let config = modeManager.remoteConfig {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(config.endpointURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        
                        if let lastConnected = config.lastConnected {
                            Text("dashboard.lastConnected".localized() + ": " + lastConnected.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    if let url = modeManager.remoteConfig?.endpointURL {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(url, forType: .string)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("action.copy".localized())
                .help("action.copy".localized())
            }
        } label: {
            Label("dashboard.remoteEndpoint".localized(), systemImage: "link")
        }
    }
    
}
