//
//  SettingsHybridNamespaceSections.swift
//  Quotio
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HybridNamespaceModelSetCard: View {
    let mapping: BaseURLNamespaceModelSet
    let isActionsDisabled: Bool
    let isDeleteInProgress: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var hostDisplay: String {
        guard let components = URLComponents(string: mapping.baseURL),
              let host = components.host else {
            return "settings.hybridNamespace.invalidHost".localized()
        }
        if let port = components.port {
            return host + ":" + String(port)
        }
        return host
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapping.namespace)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(
                        String(
                            format: "settings.hybridNamespace.host".localized(),
                            hostDisplay
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("action.edit".localized(), action: onEdit)
                        .buttonStyle(.borderless)
                        .disabled(isActionsDisabled)
                    Button(role: .destructive, action: onDelete) {
                        if isDeleteInProgress {
                            SmallProgressView()
                        } else {
                            Text("action.delete".localized())
                        }
                    }
                        .buttonStyle(.borderless)
                        .disabled(isActionsDisabled)
                }
            }
            
            Text(mapping.baseURL)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            
            if !mapping.modelSet.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: "settings.hybridNamespace.modelsCount".localized(),
                            mapping.modelSet.count
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(mapping.modelSet, id: \.self) { model in
                        Text("• \(model)")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            
            if let notes = mapping.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct HybridNamespaceModelSetEditorSheet: View {
    let title: String
    @Binding var namespace: String
    @Binding var baseURL: String
    @Binding var modelSetText: String
    @Binding var notes: String
    let validationMessages: [String]
    let isSaving: Bool
    let syncErrorMessage: String?
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var normalizedNamespace: String {
        namespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedModelSetCount: Int {
        modelSetText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private var namespaceValidationMessage: String? {
        normalizedNamespace.isEmpty
            ? "settings.hybridNamespace.validation.namespace".localized()
            : nil
    }

    private var baseURLValidationMessage: String? {
        guard let url = URL(string: normalizedBaseURL), url.scheme != nil, url.host != nil else {
            return "settings.hybridNamespace.validation.baseURL".localized()
        }
        return nil
    }

    private var modelSetValidationMessage: String? {
        parsedModelSetCount == 0
            ? "settings.hybridNamespace.validation.modelSet".localized()
            : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.hybridNamespace.editor.mappingSection".localized()) {
                    TextField("settings.hybridNamespace.editor.namespacePlaceholder".localized(), text: $namespace)
                    if let namespaceValidationMessage {
                        Label(namespaceValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.semanticWarning)
                    }
                    TextField("settings.hybridNamespace.editor.baseURLPlaceholder".localized(), text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    if let baseURLValidationMessage {
                        Label(baseURLValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.semanticWarning)
                    }
                }

                Section("settings.hybridNamespace.editor.modelSetSection".localized()) {
                    TextEditor(text: $modelSetText)
                        .frame(minHeight: 120)
                    Text("settings.hybridNamespace.editor.modelSetHelp".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            format: "settings.hybridNamespace.modelCount".localized(),
                            parsedModelSetCount
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    if let modelSetValidationMessage {
                        Label(modelSetValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.semanticWarning)
                    }
                }

                Section("settings.hybridNamespace.editor.notesSection".localized()) {
                    TextField("settings.hybridNamespace.editor.notesPlaceholder".localized(), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if !validationMessages.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(validationMessages, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.semanticWarning)
                            }
                        }
                    }
                }

                if let syncErrorMessage, !syncErrorMessage.isEmpty {
                    Section {
                        Label(
                            String(
                                format: "settings.hybridNamespace.syncError".localized(),
                                syncErrorMessage
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.semanticWarning)
                    }
                }
            }
            .navigationTitle(title)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized(), action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSave) {
                        if isSaving {
                            SmallProgressView()
                        } else {
                            Text("action.save".localized())
                        }
                    }
                    .disabled(isSaveDisabled || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .frame(minWidth: 560, minHeight: 420)
    }
}

// MARK: - Local Proxy Server Section
