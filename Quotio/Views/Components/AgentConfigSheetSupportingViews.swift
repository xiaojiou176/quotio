import SwiftUI

struct SetupModeButton: View {
    let setup: ConfigurationSetup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: setup.icon)
                    .font(.title3)
                Text(setup.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.semanticSurfaceElevated)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.borderless)
    }
}

struct BackupButton: View {
    let backup: AgentConfigurationService.BackupFile
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.callout)
                Text(backup.displayName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.semanticSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.borderless)
    }
}

struct StorageOptionButton: View {
    let option: ConfigStorageOption
    let isSelected: Bool
    let action: () -> Void

    private var displayName: String {
        switch option {
        case .jsonOnly: return "agents.storage.jsonOnly".localized()
        case .shellOnly: return "agents.storage.shellOnly".localized()
        case .both: return "agents.storage.both".localized()
        }
    }

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.title3)
                Text(displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.semanticSurfaceElevated)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.borderless)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var isMasked: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(isMasked ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct ModelSlotRow: View {
    let slot: ModelSlot
    let selectedModel: String
    let availableModels: [AvailableModel]
    let onModelChange: (String) -> Void

    private var effectiveSelection: String {
        if !selectedModel.isEmpty && availableModels.contains(where: { $0.name == selectedModel }) {
            return selectedModel
        }
        return ""
    }

    var body: some View {
        HStack {
            Text(slot.displayName)
                .font(.caption)
                .fontWeight(.medium)

            Spacer(minLength: 12)

            Picker("", selection: Binding(
                get: { effectiveSelection },
                set: { onModelChange($0) }
            )) {
                Text("agents.unspecified".localized(fallback: "未指定"))
                    .tag("")

                let groupedModels = Dictionary(grouping: availableModels) { $0.providerPresentation.displayLabel }
                let providerLabels = groupedModels.keys.sorted()

                ForEach(providerLabels, id: \.self) { providerLabel in
                    Section(header: Text(providerLabel)) {
                        ForEach((groupedModels[providerLabel] ?? []).sorted { $0.displayName < $1.displayName }) { model in
                            Text(model.displayName)
                                .tag(model.name)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 280)
            .accessibilityLabel(slot.displayName)
            .help(slot.displayName)
        }
    }
}

struct TestResultView: View {
    let result: ConnectionTestResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? Color.semanticSuccess : Color.semanticDanger)
                .accessibilityHidden(true)

            Text(result.message)
                .font(.caption)
                .foregroundStyle(result.success ? Color.semanticSuccess : Color.semanticDanger)

            Spacer()

            if let latency = result.latencyMs {
                Text("\(latency)ms")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(result.success ? Color.semanticSuccess.opacity(0.1) : Color.semanticDanger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FilePathRow: View {
    let icon: String
    let label: String
    let path: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            Text(path)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct RawConfigView: View {
    let config: RawConfigOutput
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let targetPath = config.targetPath {
                    Text(targetPath)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(config.format.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.semanticSelectionFill)
                    .foregroundStyle(Color.semanticInfo)
                    .clipShape(Capsule())

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("action.copy".localized())
                .help("action.copy".localized())
            }

            ScrollView {
                Text(config.content)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic, axes: .vertical)
            .frame(minHeight: 150, maxHeight: 320)
            .padding(12)
            .background(Color.semanticSurfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
