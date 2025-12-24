//
//  ProvidersScreen.swift
//  Quotio
//

import SwiftUI

struct ProvidersScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @State private var selectedProvider: AIProvider?
    @State private var showingOAuthSheet = false
    @State private var projectId = ""
    
    var body: some View {
        List {
            if !viewModel.proxyManager.proxyStatus.running {
                Section {
                    ContentUnavailableView {
                        Label("Proxy Not Running", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Start the proxy first to manage providers")
                    }
                }
            } else {
                // Connected Accounts
                Section {
                    if viewModel.authFiles.isEmpty {
                        Text("No accounts connected yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.authFiles, id: \.id) { file in
                            AuthFileRow(file: file)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.deleteAuthFile(file) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Label("Connected Accounts (\(viewModel.authFiles.count))", systemImage: "checkmark.seal.fill")
                }
                
                // Add Provider
                Section {
                    ForEach(AIProvider.allCases) { provider in
                        Button {
                            selectedProvider = provider
                            showingOAuthSheet = true
                        } label: {
                            HStack {
                                ProviderIcon(provider: provider, size: 24)
                                
                                Text(provider.displayName)
                                
                                Spacer()
                                
                                if let count = viewModel.authFilesByProvider[provider]?.count, count > 0 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(provider.color.opacity(0.15))
                                        .foregroundStyle(provider.color)
                                        .clipShape(Capsule())
                                }
                                
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Add Provider", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Providers")
        .sheet(isPresented: $showingOAuthSheet) {
            if let provider = selectedProvider {
                OAuthSheet(provider: provider, projectId: $projectId) {
                    showingOAuthSheet = false
                    selectedProvider = nil
                    projectId = ""
                }
            }
        }
    }
}

// MARK: - Auth File Row

struct AuthFileRow: View {
    let file: AuthFile
    
    var body: some View {
        HStack(spacing: 12) {
            if let provider = file.providerType {
                ProviderIcon(provider: provider, size: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.email ?? file.name)
                    .fontWeight(.medium)
                
                HStack(spacing: 6) {
                    Text(file.provider.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Circle()
                        .fill(file.statusColor)
                        .frame(width: 6, height: 6)
                    
                    Text(file.status)
                        .font(.caption)
                        .foregroundStyle(file.statusColor)
                }
            }
            
            Spacer()
            
            if file.disabled {
                Text("Disabled")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - OAuth Sheet

struct OAuthSheet: View {
    @Environment(QuotaViewModel.self) private var viewModel
    let provider: AIProvider
    @Binding var projectId: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ProviderIcon(provider: provider, size: 48)
            
            Text("Connect \(provider.displayName)")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Authenticate with your \(provider.displayName) account")
                .foregroundStyle(.secondary)
            
            if provider == .gemini {
                TextField("Project ID (optional)", text: $projectId)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            
            if let state = viewModel.oauthState, state.provider == provider {
                switch state.status {
                case .waiting, .polling:
                    ProgressView("Waiting for authentication...")
                    
                case .success:
                    Label("Connected successfully!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    
                case .error:
                    Label(state.error ?? "Authentication failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Authenticate") {
                    Task {
                        await viewModel.startOAuth(for: provider, projectId: projectId.isEmpty ? nil : projectId)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(provider.color)
                .disabled(viewModel.oauthState?.status == .polling)
            }
        }
        .padding(40)
        .frame(width: 450)
    }
}
