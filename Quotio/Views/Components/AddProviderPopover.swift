//
//  AddProviderPopover.swift
//  Quotio
//
//  Popover with grid layout for adding new provider accounts.
//  Part of ProvidersScreen UI/UX redesign.
//

import SwiftUI

@MainActor
private enum AddProviderPopoverL10n {
    static func text(_ key: String, fallback: String) -> String {
        let localized = key.localized()
        return localized == key ? fallback : localized
    }

    static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        let template = text(key, fallback: fallback)
        return String(format: template, locale: Locale.current, arguments: arguments)
    }
}

// MARK: - Add Provider Popover

@MainActor
struct AddProviderPopover: View {
    let providers: [AIProvider]
    let existingCounts: [AIProvider: Int]  // Number of existing accounts per provider
    var onSelectProvider: (AIProvider) -> Void
    var onScanIDEs: () -> Void
    var onAddCustomProvider: () -> Void
    var onDismiss: () -> Void

    @State private var selectedProvider: AIProvider?
    @State private var hasAttemptedSubmit = false
    @State private var hasAcknowledgedGeminiRisk = false

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 12)
    ]

    private var showsGeminiOverwriteWarning: Bool {
        providers.contains(.gemini)
    }

    private var selectedProviderExistingCount: Int {
        guard let selectedProvider else { return 0 }
        return existingCounts[selectedProvider] ?? 0
    }

    private var selectedProviderHasExistingAccounts: Bool {
        selectedProviderExistingCount > 0
    }

    private var requiresGeminiRiskAcknowledgement: Bool {
        selectedProvider == .gemini && selectedProviderHasExistingAccounts
    }

    private var canSubmit: Bool {
        guard selectedProvider != nil else { return false }
        if requiresGeminiRiskAcknowledgement && !hasAcknowledgedGeminiRisk {
            return false
        }
        return true
    }

    private var submitDisabledReason: String? {
        if selectedProvider == nil {
            return AddProviderPopoverL10n.text(
                "providers.addPopover.validation.selectProvider",
                fallback: "Select one provider to continue."
            )
        }
        if requiresGeminiRiskAcknowledgement && !hasAcknowledgedGeminiRisk {
            return AddProviderPopoverL10n.text(
                "providers.addPopover.validation.geminiAcknowledge",
                fallback: "Review Gemini coexist/overwrite risk and confirm before continuing."
            )
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("providers.addAccount".localized())
                .font(.headline)

            // Hint: can add multiple accounts
            Text("providers.addMultipleHint".localized())
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsGeminiOverwriteWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 1)

                    Text("providers.gemini.tip.multiCredential".localized())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.08))
                )
            }

            // Provider grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(providers) { provider in
                    ProviderButton(
                        provider: provider,
                        existingCount: existingCounts[provider] ?? 0,
                        isSelected: selectedProvider == provider
                    ) {
                        selectProvider(provider)
                    }
                }
            }

            selectionFeedbackView

            if requiresGeminiRiskAcknowledgement {
                Toggle(isOn: $hasAcknowledgedGeminiRisk) {
                    Text(
                        AddProviderPopoverL10n.text(
                            "providers.addPopover.gemini.confirmRisk",
                            fallback: "I understand this Gemini credential may coexist with or overwrite an existing account entry."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.primary)
                }
                .toggleStyle(.checkbox)
            }

            Divider()

            // Scan for IDEs option
            Button {
                onScanIDEs()
                onDismiss()
            } label: {
                HStack {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(.blue)
                    Text("ideScan.scanExisting".localized())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.menuRow)
            .focusEffectDisabled()

            // Add Custom Provider option
            Button {
                onAddCustomProvider()
                onDismiss()
            } label: {
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.purple)
                    Text("customProviders.add".localized())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.menuRow)
            .focusEffectDisabled()

            Divider()

            HStack(spacing: 12) {
                Button("action.cancel".localized()) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    submitSelection()
                } label: {
                    Text(
                        AddProviderPopoverL10n.text(
                            "providers.addPopover.cta.continue",
                            fallback: "Continue"
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }

            if let submitDisabledReason {
                Label(
                    submitDisabledReason,
                    systemImage: hasAttemptedSubmit ? "exclamationmark.triangle.fill" : "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(hasAttemptedSubmit ? .red : .secondary)
            }
        }
        .padding(16)
        .frame(width: 360)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var selectionFeedbackView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedProvider {
                Label(
                    AddProviderPopoverL10n.format(
                        "providers.addPopover.selection.currentProvider",
                        fallback: "Selected provider: %@",
                        selectedProvider.displayName.localized()
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(selectedProvider.color)

                if selectedProviderHasExistingAccounts {
                    Label(
                        AddProviderPopoverL10n.format(
                            "providers.addPopover.selection.existingAccountCount",
                            fallback: "%@ already has %d account(s).",
                            selectedProvider.displayName.localized(),
                            selectedProviderExistingCount
                        ),
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)

                    Text(
                        AddProviderPopoverL10n.text(
                            "providers.addPopover.selection.coexistOrOverwriteHint",
                            fallback: "New credentials can coexist, but some gateway versions may treat duplicates as overwrite candidates."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if selectedProvider == .gemini {
                        Text("providers.gemini.tip.identity".localized())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("providers.gemini.tip.keepBoth".localized())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Label(
                        AddProviderPopoverL10n.format(
                            "providers.addPopover.selection.readyToSubmit",
                            fallback: "%@ is ready to be added.",
                            selectedProvider.displayName.localized()
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.green)
                }
            } else {
                Label(
                    AddProviderPopoverL10n.text(
                        "providers.addPopover.validation.selectProvider",
                        fallback: "Select one provider to continue."
                    ),
                    systemImage: hasAttemptedSubmit ? "exclamationmark.triangle.fill" : "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(hasAttemptedSubmit ? .red : .secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func selectProvider(_ provider: AIProvider) {
        if selectedProvider != provider {
            hasAcknowledgedGeminiRisk = false
        }
        selectedProvider = provider
        hasAttemptedSubmit = false
    }

    private func submitSelection() {
        hasAttemptedSubmit = true
        guard canSubmit, let selectedProvider else { return }
        onSelectProvider(selectedProvider)
        onDismiss()
    }
}

// MARK: - Provider Button

@MainActor
private struct ProviderButton: View {
    let provider: AIProvider
    let existingCount: Int  // Number of existing accounts for this provider
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ProviderIcon(provider: provider, size: 32)

                    // Badge showing existing account count
                    if existingCount > 0 {
                        Text(
                            AddProviderPopoverL10n.format(
                                "providers.addPopover.selection.existingBadge",
                                fallback: "%d",
                                existingCount
                            )
                        )
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(provider.color)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(provider.color)
                            .offset(x: 8, y: 8)
                    }
                }

                Text(provider.displayName.localized())
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 80, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? provider.color.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? provider.color.opacity(0.8) : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.gridItem(hoverColor: provider.color.opacity(0.1)))
        .focusEffectDisabled()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddProviderPopover(
        providers: AIProvider.allCases.filter { $0.supportsManualAuth },
        existingCounts: [.claude: 2, .antigravity: 1],  // Preview with some existing accounts
        onSelectProvider: { provider in
            print("Selected: \(provider.displayName)")
        },
        onScanIDEs: {
            print("Scan IDEs")
        },
        onAddCustomProvider: {
            print("Add Custom Provider")
        },
        onDismiss: {}
    )
}
