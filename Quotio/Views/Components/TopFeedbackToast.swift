//
//  TopFeedbackToast.swift
//  Quotio
//

import SwiftUI

enum TopFeedbackRhythm {
    static let reducedMotionMilliseconds: Int = 120
    static let calmMilliseconds: Int = 220
    static let crispMilliseconds: Int = 160

    static func pulseMilliseconds(
        reduceMotion: Bool,
        profile: QuotioMotionProfile = .default
    ) -> Int {
        guard !reduceMotion else { return reducedMotionMilliseconds }
        return profile == .crisp ? crispMilliseconds : calmMilliseconds
    }

    static func pulseAnimation(
        reduceMotion: Bool,
        profile: QuotioMotionProfile = .default
    ) -> Animation {
        let targetDuration = max(0.001, Double(pulseMilliseconds(reduceMotion: reduceMotion, profile: profile)) / 1000)
        return QuotioMotion.contentSwap.speed(QuotioMotion.Duration.contentSwap / targetDuration)
    }
}

enum TopFeedbackTone {
    case success
    case destructiveSuccess
    case error

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .destructiveSuccess:
            return "trash.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .success:
            return Color.semanticSuccess
        case .destructiveSuccess:
            return Color.semanticDanger
        case .error:
            return Color.semanticDanger
        }
    }

    var autoDismissSeconds: TimeInterval? {
        switch self {
        case .success:
            return 3
        case .destructiveSuccess:
            return 3
        case .error:
            return nil
        }
    }

    var accessibilityStatusText: String {
        switch self {
        case .success:
            return "status.success".localized(fallback: "成功")
        case .destructiveSuccess:
            return "status.success".localized(fallback: "成功")
        case .error:
            return "status.error".localized(fallback: "错误")
        }
    }
}

struct TopFeedbackItem: Equatable {
    let message: String
    let tone: TopFeedbackTone

    static func success(_ message: String) -> TopFeedbackItem {
        TopFeedbackItem(message: message, tone: .success)
    }

    static func destructiveSuccess(_ message: String) -> TopFeedbackItem {
        TopFeedbackItem(message: message, tone: .destructiveSuccess)
    }

    static func error(_ message: String) -> TopFeedbackItem {
        TopFeedbackItem(message: message, tone: .error)
    }
}

struct TopFeedbackToast: View {
    let item: TopFeedbackItem
    @Binding var isAutoDismissPaused: Bool
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(QuotioMotionProfileStorage.key) private var motionProfileRaw = QuotioMotionProfile.default.rawValue
    @AccessibilityFocusState private var isAccessibilityFocused: Bool
    @State private var emphasizeIcon = false
    @State private var emphasisTask: Task<Void, Never>?
    @State private var isHovering = false
    @State private var toneGlowOpacity: Double = 0
    
    private var motionProfile: QuotioMotionProfile {
        QuotioMotionProfile(rawValue: motionProfileRaw) ?? .default
    }

    private var toneHaloPeakOpacity: Double {
        switch item.tone {
        case .success:
            return 0.16
        case .destructiveSuccess:
            return 0.2
        case .error:
            return 0.28
        }
    }
    
    @ViewBuilder
    private var dismissButton: some View {
        if item.tone.autoDismissSeconds == nil {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.dismiss".localized(fallback: "关闭"))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: TopFeedbackTone.success.iconName)
                    .opacity(item.tone == .success ? 1 : 0)
                    .foregroundStyle(TopFeedbackTone.success.tintColor)
                Image(systemName: TopFeedbackTone.destructiveSuccess.iconName)
                    .opacity(item.tone == .destructiveSuccess ? 1 : 0)
                    .foregroundStyle(TopFeedbackTone.destructiveSuccess.tintColor)
                Image(systemName: TopFeedbackTone.error.iconName)
                    .opacity(item.tone == .error ? 1 : 0)
                    .foregroundStyle(TopFeedbackTone.error.tintColor)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 18, height: 18)
            .scaleEffect(emphasizeIcon ? (motionProfile == .crisp ? 1.07 : 1.1) : 1.0)
            .opacity(emphasizeIcon ? (motionProfile == .crisp ? 0.96 : 0.94) : 1.0)
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: item.tone)
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: emphasizeIcon)

            Text(item.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            dismissButton
        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(item.tone.tintColor.opacity(0.24 + toneGlowOpacity * 0.55), lineWidth: 1)
            )
            .shadow(color: item.tone.tintColor.opacity(0.12 + toneGlowOpacity * 0.35), radius: 8, x: 0, y: 3)
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: toneGlowOpacity)
            .padding(.top, 8)
            .padding(.horizontal, 12)
            .transition(QuotioMotion.Transition.pageEnter(reduceMotion: reduceMotion))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.message)
            .accessibilityValue(item.tone.accessibilityStatusText)
            .accessibilityHint("feedback.toast.hint".localized(fallback: "悬停时将暂停自动关闭"))
            .accessibilityFocused($isAccessibilityFocused)
            .onHover { hovered in
                isHovering = hovered
                updateAutoDismissPaused(hovered: isHovering, focused: isAccessibilityFocused)
            }
            .onAppear {
                triggerIconEmphasis()
                updateAutoDismissPaused(hovered: isHovering, focused: isAccessibilityFocused)
            }
            .onChange(of: item.message) { _, _ in
                triggerIconEmphasis()
            }
            .onChange(of: item.tone) { _, _ in
                triggerIconEmphasis()
            }
            .onChange(of: isAccessibilityFocused) { _, focused in
                updateAutoDismissPaused(hovered: isHovering, focused: focused)
            }
            .onDisappear {
                emphasisTask?.cancel()
                isAutoDismissPaused = false
            }
    }

    private func triggerIconEmphasis() {
        emphasisTask?.cancel()
        if reduceMotion {
            emphasizeIcon = false
            toneGlowOpacity = 0
            return
        }
        emphasizeIcon = true
        toneGlowOpacity = toneHaloPeakOpacity
        emphasisTask = Task {
            try? await Task.sleep(for: .milliseconds(TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion, profile: motionProfile)))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                emphasizeIcon = false
                toneGlowOpacity = 0
            }
        }
    }

    private func updateAutoDismissPaused(hovered: Bool, focused: Bool) {
        isAutoDismissPaused = hovered || focused
    }
}

struct TopFeedbackBanner: View {
    @Binding var item: TopFeedbackItem?
    @State private var dismissTask: Task<Void, Never>?
    @State private var isAutoDismissPaused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(QuotioMotionProfileStorage.key) private var motionProfileRaw = QuotioMotionProfile.default.rawValue
    
    private var motionProfile: QuotioMotionProfile {
        QuotioMotionProfile(rawValue: motionProfileRaw) ?? .default
    }

    var body: some View {
        Group {
            if let currentItem = item {
                TopFeedbackToast(item: currentItem, isAutoDismissPaused: $isAutoDismissPaused) {
                    dismiss()
                }
                .quotioAppearFeedback(offsetY: -10, initialOpacity: 0.25)
            }
        }
        .onAppear {
            scheduleDismiss(for: item)
        }
        .onChange(of: item) { _, newItem in
            scheduleDismiss(for: newItem)
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func scheduleDismiss(for item: TopFeedbackItem?) {
        dismissTask?.cancel()
        guard let item, let delaySeconds = dismissalDelaySeconds(for: item) else {
            return
        }

        dismissTask = Task { @MainActor in
            var elapsed: TimeInterval = 0
            let tickSeconds: TimeInterval = 0.2
            let tickNanoseconds = UInt64(tickSeconds * 1_000_000_000)
            while elapsed < delaySeconds {
                try? await Task.sleep(nanoseconds: tickNanoseconds)
                guard !Task.isCancelled else { return }
                if !isAutoDismissPaused {
                    elapsed += tickSeconds
                }
            }
            dismiss()
        }
    }

    private func dismissalDelaySeconds(for item: TopFeedbackItem) -> TimeInterval? {
        guard let base = item.tone.autoDismissSeconds else { return nil }
        let messageBonus = min(2.0, Double(item.message.count) * 0.03)
        let accessibilityBonus: TimeInterval = reduceMotion ? 1.0 : 0
        return base + messageBonus + accessibilityBonus
    }

    private func dismiss() {
        dismissTask?.cancel()
        withMotionAwareAnimation(QuotioMotion.dismiss, reduceMotion: reduceMotion) {
            item = nil
        }
    }
}
