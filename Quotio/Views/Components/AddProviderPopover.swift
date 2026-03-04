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
    @State private var selectionPulse = false
    @State private var blockedSubmitPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                fallback: "请选择一个提供商后继续。"
            )
        }
        if requiresGeminiRiskAcknowledgement && !hasAcknowledgedGeminiRisk {
            return AddProviderPopoverL10n.text(
                "providers.addPopover.validation.geminiAcknowledge",
                fallback: "请先阅读 Gemini 共存/覆盖风险并确认后继续。"
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
                        .foregroundStyle(Color.semanticWarning)
                        .padding(.top, 4)

                    Text("providers.gemini.tip.multiCredential".localized())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.semanticWarningFill)
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
                            fallback: "我已了解该 Gemini 凭据可能与现有账号共存，或覆盖现有账号记录。"
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
                        .foregroundStyle(Color.semanticInfo)
                    Text("ideScan.scanExisting".localized())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.menuRow)

            // Add Custom Provider option
            Button {
                onAddCustomProvider()
                onDismiss()
            } label: {
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(Color.semanticAccentSecondary)
                    Text("customProviders.add".localized())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.menuRow)

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
                    HStack(spacing: 6) {
                        Image(systemName: canSubmit ? "arrow.right.circle.fill" : "arrow.right.circle")
                        Text(
                            AddProviderPopoverL10n.text(
                                "providers.addPopover.cta.continue",
                                fallback: "继续"
                            )
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .buttonStyle(.borderedProminent)
                .tint(selectedProvider?.color ?? Color.accentColor)
                .scaleEffect(blockedSubmitPulse ? 0.985 : 1.0)
                .motionAwareAnimation(TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion), value: blockedSubmitPulse)
            }

            if let submitDisabledReason {
                Label(
                    submitDisabledReason,
                    systemImage: hasAttemptedSubmit ? "exclamationmark.triangle.fill" : "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(hasAttemptedSubmit ? Color.semanticDanger : .secondary)
                .transition(QuotioMotion.Transition.contentSwap(reduceMotion: reduceMotion))
            }
        }
        .padding(16)
        .frame(width: 360)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: selectedProvider?.rawValue ?? "__none__")
        .motionAwareAnimation(QuotioMotion.contentSwap, value: hasAttemptedSubmit)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: hasAcknowledgedGeminiRisk)
    }

    @ViewBuilder
    private var selectionFeedbackView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedProvider {
                Label(
                    AddProviderPopoverL10n.format(
                        "providers.addPopover.selection.currentProvider",
                        fallback: "已选提供商：%@",
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
                            fallback: "%@ 已有 %d 个账号。",
                            selectedProvider.displayName.localized(),
                            selectedProviderExistingCount
                        ),
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.semanticWarning)

                    Text(
                        AddProviderPopoverL10n.text(
                            "providers.addPopover.selection.coexistOrOverwriteHint",
                            fallback: "新凭据可以共存，但部分网关版本会把重复条目视为覆盖候选。"
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
                            fallback: "%@ 已准备好添加。",
                            selectedProvider.displayName.localized()
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.semanticSuccess)
                }
            } else {
                Label(
                    AddProviderPopoverL10n.text(
                        "providers.addPopover.validation.selectProvider",
                        fallback: "请选择一个提供商后继续。"
                    ),
                    systemImage: hasAttemptedSubmit ? "exclamationmark.triangle.fill" : "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(hasAttemptedSubmit ? Color.semanticDanger : .secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
        .scaleEffect(selectionPulse ? 1.01 : 1)
        .motionAwareAnimation(TopFeedbackRhythm.pulseAnimation(reduceMotion: reduceMotion), value: selectionPulse)
    }

    private func selectProvider(_ provider: AIProvider) {
        if selectedProvider != provider {
            hasAcknowledgedGeminiRisk = false
        }
        selectedProvider = provider
        hasAttemptedSubmit = false
        blockedSubmitPulse = false
        selectionPulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
            await MainActor.run {
                selectionPulse = false
            }
        }
    }

    private func submitSelection() {
        hasAttemptedSubmit = true
        guard canSubmit, let selectedProvider else {
            blockedSubmitPulse = true
            Task {
                try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)))
                await MainActor.run {
                    blockedSubmitPulse = false
                }
            }
            return
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                            .foregroundStyle(Color.semanticOnAccent)
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
            .scaleEffect(isSelected ? (reduceMotion ? 1 : 1.02) : 1)
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: isSelected)
        }
        .buttonStyle(.gridItem(hoverColor: provider.color.opacity(0.1)))
        .onHover { hovering in
            withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "providers.addPopover.providerButton.label".localizedFormat(
                fallback: "%@，%d 个账号",
                provider.displayName.localized(),
                existingCount
            )
        )
        .accessibilityValue(
            isSelected
                ? "providers.addPopover.providerButton.selected".localized(fallback: "已选中")
                : "providers.addPopover.providerButton.notSelected".localized(fallback: "未选中")
        )
    }
}

// MARK: - Preview

#Preview {
    AddProviderPopover(
        providers: AIProvider.allCases.filter { $0.supportsManualAuth },
        existingCounts: [.claude: 2, .antigravity: 1],  // Preview with some existing accounts
        onSelectProvider: { _ in },
        onScanIDEs: {},
        onAddCustomProvider: {},
        onDismiss: {}
    )
}
