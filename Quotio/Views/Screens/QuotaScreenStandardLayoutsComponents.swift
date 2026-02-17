//
//  QuotaScreenStandardLayoutsComponents.swift
//  Quotio
//

import SwiftUI

// MARK: - Standard Lowest Bar Layout

struct StandardLowestBarLayout: View {
    let models: [ModelQuota]

    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }

    private var sorted: [ModelQuota] {
        models.sorted { $0.percentage < $1.percentage }
    }

    private var lowest: ModelQuota? {
        sorted.first
    }

    private var others: [ModelQuota] {
        Array(sorted.dropFirst())
    }

    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let lowest = lowest {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(lowest.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "%.0f%%", displayPercent(for: lowest.percentage)))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(displayHelper.statusTint(remainingPercent: lowest.percentage))
                            .monospacedDigit()
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(displayHelper.statusTint(remainingPercent: lowest.percentage).gradient)
                                .frame(width: proxy.size.width * (displayPercent(for: lowest.percentage) / 100))
                        }
                    }
                    .frame(height: 8)

                    if lowest.formattedResetTime != "—" && !lowest.formattedResetTime.isEmpty {
                        Text(lowest.formattedResetTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .background(displayHelper.statusTint(remainingPercent: lowest.percentage).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !others.isEmpty {
                VStack(spacing: 4) {
                    ForEach(others) { model in
                        HStack {
                            Text(model.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if model.formattedResetTime != "—" && !model.formattedResetTime.isEmpty {
                                Text(model.formattedResetTime)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(String(format: "%.0f%%", displayPercent(for: model.percentage)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(displayHelper.statusTint(remainingPercent: model.percentage))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Standard Ring Layout

struct StandardRingLayout: View {
    let models: [ModelQuota]

    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }

    private var columns: [GridItem] {
        let count = min(max(models.count, 1), 4)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(models, id: \.id) { model in
                VStack(spacing: 6) {
                    RingProgressView(
                        percent: displayPercent(for: model.percentage),
                        size: 44,
                        lineWidth: 5,
                        tint: displayHelper.statusTint(remainingPercent: model.percentage),
                        showLabel: true
                    )

                    Text(model.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if model.formattedResetTime != "—" && !model.formattedResetTime.isEmpty {
                        Text(model.formattedResetTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Antigravity Models Detail Sheet

struct AntigravityModelsDetailSheet: View {
    let email: String
    let models: [ModelQuota]

    @Environment(\.dismiss) private var dismiss

    private var sortedModels: [ModelQuota] {
        models.sorted { $0.percentage < $1.percentage }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), alignment: .leading),
            GridItem(.fixed(80), alignment: .trailing),
            GridItem(.fixed(90), alignment: .trailing)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(email)
                        .font(.headline)
                    Text("quota.models.detail.subtitle".localized(fallback: "模型详情"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("action.done".localized()) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    Text("quota.models.detail.model".localized(fallback: "模型"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("quota.models.detail.remaining".localized(fallback: "剩余"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("quota.models.detail.reset".localized(fallback: "重置"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(sortedModels, id: \.id) { model in
                        ModelDetailCard(model: model)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - Model Detail Row

struct ModelDetailCard: View {
    let model: ModelQuota

    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }

    private var remainingPercent: Double {
        max(0, min(100, model.percentage))
    }

    var body: some View {
        Text(model.displayName)
            .font(.caption)
            .lineLimit(1)

        Text(String(format: "%.0f%%", displayHelper.displayPercent(remainingPercent: remainingPercent)))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(displayHelper.statusTint(remainingPercent: remainingPercent))
            .monospacedDigit()

        Text(model.formattedResetTime)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: - Usage Row

struct UsageRowV2: View {
    let name: String
    let icon: String?
    let usedPercent: Double
    let used: Int?
    let limit: Int?
    let resetTime: String
    let tooltip: String?

    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }

    private var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    private var usageText: String {
        if let used, let limit, limit > 0 {
            return "\(used)/\(limit)"
        }
        if let used {
            return "\(used)"
        }
        return "—"
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(name)
                        .font(.subheadline)
                }

                HStack(spacing: 8) {
                    Text(usageText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(resetTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(String(format: "%.0f%%", displayHelper.displayPercent(remainingPercent: remainingPercent)))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(displayHelper.statusTint(remainingPercent: remainingPercent))
                .monospacedDigit()
        }
        .help(tooltip ?? resetTime)
    }
}

// MARK: - Loading View

struct QuotaLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private var skeletonOpacity: Double {
        if reduceMotion {
            return 0.35
        }
        return isAnimating ? 0.5 : 0.2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(skeletonOpacity))
                        .frame(height: 16)
                        .frame(maxWidth: 120)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(skeletonOpacity * 0.9))
                        .frame(height: 10)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(skeletonOpacity * 0.7))
                        .frame(height: 10)
                        .frame(maxWidth: .infinity)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .motionAwareAnimation(
            .easeInOut(duration: 1).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
        }
    }
}
