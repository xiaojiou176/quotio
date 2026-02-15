//
//  APIKeysScreen.swift
//  Quotio
//

import SwiftUI
import AppKit

struct APIKeysScreen: View {
    @Environment(QuotaViewModel.self) private var viewModel
    
    @State private var newAPIKey: String = ""
    @State private var editingKeyIndex: Int? = nil
    @State private var editedKeyValue: String = ""
    @State private var showingAddKey: Bool = false
    
    var body: some View {
        Group {
            if !viewModel.proxyManager.proxyStatus.running {
                proxyNotRunningView
            } else {
                apiKeysListView
            }
        }
        .navigationTitle("nav.apiKeys".localized())
        .toolbar {
            if viewModel.proxyManager.proxyStatus.running {
                ToolbarItemGroup {
                    Button {
                        newAPIKey = generateRandomKey()
                        showingAddKey = true
                    } label: {
                        Label("apiKeys.generate".localized(), systemImage: "wand.and.stars")
                    }
                    .help("apiKeys.generateHelp".localized())
                    
                    Button {
                        showingAddKey = true
                    } label: {
                        Label("apiKeys.add".localized(), systemImage: "plus")
                    }
                    .help("apiKeys.addHelp".localized())
                }
            }
        }
    }
    
    private var proxyNotRunningView: some View {
        ProxyRequiredView(
            description: "apiKeys.proxyRequired".localized()
        ) {
            await viewModel.startProxy()
        }
    }
    
    private var apiKeysListView: some View {
        Group {
            if viewModel.isLoading && viewModel.apiKeys.isEmpty {
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text("action.loading".localized(fallback: "加载中..."))
                }
            } else if let errorMessage = viewModel.errorMessage, viewModel.apiKeys.isEmpty {
                ContentUnavailableView {
                    Label("status.error".localized(fallback: "加载失败"), systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("action.retry".localized(fallback: "重试")) {
                        Task { await viewModel.fetchAPIKeys() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                apiKeysListContent
            }
        }
    }

    private var apiKeysListContent: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.semanticWarning)
                }
            } else if !viewModel.apiKeys.isEmpty {
                Section {
                    Label("status.connected".localized(fallback: "操作成功"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.semanticSuccess)
                }
            }

            Section {
                ForEach(Array(viewModel.apiKeys.enumerated()), id: \.offset) { index, key in
                    APIKeyRow(
                        key: key,
                        isEditing: editingKeyIndex == index,
                        editedValue: $editedKeyValue,
                        onEdit: {
                            editingKeyIndex = index
                            editedKeyValue = key
                        },
                        onSave: {
                            Task {
                                await viewModel.updateAPIKey(old: key, new: editedKeyValue)
                                editingKeyIndex = nil
                                editedKeyValue = ""
                            }
                        },
                        onCancel: {
                            editingKeyIndex = nil
                            editedKeyValue = ""
                        },
                        onCopy: {
                            copyToClipboard(key)
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteAPIKey(key)
                            }
                        }
                    )
                }
                
                if showingAddKey {
                    AddAPIKeyRow(
                        newKey: $newAPIKey,
                        onSave: addNewKey,
                        onCancel: {
                            showingAddKey = false
                            newAPIKey = ""
                        },
                        onGenerate: {
                            newAPIKey = generateRandomKey()
                        }
                    )
                }
            } header: {
                HStack {
                    Text("apiKeys.list".localized())
                    Spacer()
                    Text("\(viewModel.apiKeys.count)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("apiKeys.description".localized())
            }
        }
        .overlay {
            if viewModel.apiKeys.isEmpty && !showingAddKey && !viewModel.isLoading && viewModel.errorMessage == nil {
                ContentUnavailableView {
                    Label("apiKeys.empty".localized(), systemImage: "key.slash")
                } description: {
                    Text("apiKeys.emptyDescription".localized())
                } actions: {
                    Button {
                        newAPIKey = generateRandomKey()
                        showingAddKey = true
                    } label: {
                        Text("apiKeys.generateFirst".localized())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private func addNewKey() {
        let trimmed = newAPIKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        Task {
            await viewModel.addAPIKey(trimmed)
            newAPIKey = ""
            showingAddKey = false
        }
    }
    
    private func generateRandomKey() -> String {
        let prefix = "sk-"
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomPart = String((0..<32).map { _ in characters.randomElement()! })
        return prefix + randomPart
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct APIKeyRow: View {
    let key: String
    let isEditing: Bool
    @Binding var editedValue: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            if isEditing {
                TextField("apiKeys.placeholder".localized(), text: $editedValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(onSave)
                
                Button(action: onSave) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.semanticSuccess)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("action.save".localized(fallback: "保存"))
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("action.cancel".localized())
            } else {
                Text(maskedKey)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                
                Spacer()
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("action.copy".localized())
                .accessibilityLabel("action.copy".localized())
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("apiKeys.edit".localized())
                .accessibilityLabel("apiKeys.edit".localized())
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.semanticDanger)
                }
                .buttonStyle(.borderless)
                .help("action.delete".localized())
                .accessibilityLabel("action.delete".localized())
            }
        }
        .padding(.vertical, 4)
    }
    
    private var maskedKey: String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        let prefix = String(key.prefix(6))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
}

struct AddAPIKeyRow: View {
    @Binding var newKey: String
    let onSave: () -> Void
    let onCancel: () -> Void
    let onGenerate: () -> Void
    
    var body: some View {
        HStack {
            TextField("apiKeys.placeholder".localized(), text: $newKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(onSave)
            
            Button(action: onGenerate) {
                Image(systemName: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .help("apiKeys.generate".localized())
            .accessibilityLabel("apiKeys.generate".localized())
            
            Button(action: onSave) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.semanticSuccess)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("action.save".localized(fallback: "保存"))
            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
            
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("action.cancel".localized())
        }
        .padding(.vertical, 4)
    }
}
