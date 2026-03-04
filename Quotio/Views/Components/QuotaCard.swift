//
//  QuotaCard.swift
//  Quotio
//

import SwiftUI

struct QuotaCard: View {
    let provider: AIProvider
    let accounts: [AuthFile]
    var quotaData: [String: ProviderQuotaData]?
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerFeedbackScale: CGFloat = 1
    @State private var headerFeedbackOpacity: Double = 0
    @State private var isCardHovered = false
    
    private var readyCount: Int {
        accounts.filter { $0.status == "ready" && !$0.disabled }.count
    }
    
    private var coolingCount: Int {
        accounts.filter { $0.status == "cooling" }.count
    }
    
    private var errorCount: Int {
        accounts.filter { $0.status == "error" || $0.unavailable }.count
    }
    
    private var hasRealQuotaData: Bool {
        guard let quotaData = quotaData else { return false }
        return quotaData.values.contains { !$0.models.isEmpty }
    }
    
    private var aggregatedModels: [String: (remainingPercent: Double, resetTime: String, count: Int)] {
        guard let quotaData = quotaData else { return [:] }
        
        var result: [String: (total: Double, resetTime: String, count: Int)] = [:]
        
        for (_, data) in quotaData {
            for model in data.models {
                let existing = result[model.name] ?? (total: 0, resetTime: model.formattedResetTime, count: 0)
                result[model.name] = (
                    total: existing.total + Double(model.percentage),
                    resetTime: model.formattedResetTime,
                    count: existing.count + 1
                )
            }
        }
        
        return result.mapValues { value in
            (remainingPercent: value.total / Double(max(value.count, 1)), resetTime: value.resetTime, count: value.count)
        }
    }

    private var statusLabel: String {
        if readyCount > 0 {
            return "quota.status.ready".localized(fallback: "可用")
        }
        if coolingCount > 0 {
            return "quota.status.cooling".localized(fallback: "冷却中")
        }
        return "quota.status.error".localized(fallback: "错误")
    }

    private enum SummaryStatus: Equatable {
        case ready
        case cooling
        case error
    }

    private var summaryStatus: SummaryStatus {
        if readyCount > 0 { return .ready }
        if coolingCount > 0 { return .cooling }
        return .error
    }

    private var summarySymbolName: String {
        switch summaryStatus {
        case .ready:
            return "checkmark.circle.fill"
        case .cooling:
            return "clock.badge.exclamationmark"
        case .error:
            return "xmark.circle.fill"
        }
    }

    private var summaryTint: Color {
        switch summaryStatus {
        case .ready:
            return .semanticSuccess
        case .cooling:
            return .semanticWarning
        case .error:
            return .semanticDanger
        }
    }

    private func triggerSummaryFeedback(for newStatus: SummaryStatus) {
        guard !reduceMotion, newStatus != .cooling else {
            headerFeedbackScale = 1
            headerFeedbackOpacity = 0
            return
        }

        let peakOpacity: Double = newStatus == .error ? 0.32 : 0.24
        let peakScale: CGFloat = newStatus == .error ? 1.08 : 1.05
        headerFeedbackScale = 0.97
        headerFeedbackOpacity = 0

        withMotionAwareAnimation(QuotioMotion.successEmphasis, reduceMotion: reduceMotion) {
            headerFeedbackScale = peakScale
            headerFeedbackOpacity = peakOpacity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withMotionAwareAnimation(QuotioMotion.contentSwap, reduceMotion: reduceMotion) {
                headerFeedbackScale = 1
                headerFeedbackOpacity = 0
            }
        }
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                
                if hasRealQuotaData {
                    realQuotaSection
                } else {
                    estimatedQuotaSection
                }
                
                Divider()
                
                statusBreakdownSection
                
                accountListSection
            }
            .padding(4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    uiExperience.highContrastEnabled
                    ? Color.primary.opacity(0.35)
                    : summaryTint.opacity(isCardHovered ? 0.18 : 0.1),
                    lineWidth: 1
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(summaryTint.opacity(isCardHovered ? 0.04 : 0))
        )
        .onHover { hovering in
            withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                isCardHovered = hovering
            }
        }
        .motionAwareAnimation(QuotioMotion.hover, value: isCardHovered)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            ProviderIcon(provider: provider, size: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline)
                Text("quota.accounts.count".localized(fallback: "\(accounts.count) 个账号"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: summarySymbolName)
                    .font(.caption)
                    .foregroundStyle(summaryTint)
                    .accessibilityHidden(true)
                Text(statusLabel)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(summaryTint.opacity(headerFeedbackOpacity), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(summaryTint.opacity(0.24), lineWidth: 0.8)
            )
            .scaleEffect(headerFeedbackScale)
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: headerFeedbackScale)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("quota.status.summary".localized(fallback: "状态摘要"))
            .accessibilityValue(statusLabel)
        }
        .onChange(of: summaryStatus) { oldStatus, newStatus in
            guard oldStatus != newStatus else { return }
            triggerSummaryFeedback(for: newStatus)
        }
    }
    
    // MARK: - Real Quota (from API)
    
    private var realQuotaSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(aggregatedModels.keys.sorted()), id: \.self) { modelName in
                if let data = aggregatedModels[modelName] {
                    let displayName = ModelQuota(name: modelName, percentage: 0.0, resetTime: "").displayName
                    QuotaSection(
                        title: displayName,
                        remainingPercent: data.remainingPercent,
                        resetTime: data.resetTime,
                        tint: data.remainingPercent > 50 ? Color.semanticSuccess : (data.remainingPercent > 20 ? Color.semanticWarning : Color.semanticDanger)
                    )
                }
            }
        }
    }
    
    // MARK: - Estimated Quota (fallback)
    
    private var estimatedQuotaSection: some View {
        VStack(spacing: 12) {
            QuotaSection(
                title: "quota.session".localized(fallback: "会话"),
                remainingPercent: sessionRemainingPercent,
                resetTime: sessionResetTime,
                tint: sessionRemainingPercent > 50 ? Color.semanticSuccess : (sessionRemainingPercent > 20 ? Color.semanticWarning : Color.semanticDanger)
            )
            
            if provider == .claude || provider == .codex {
                QuotaSection(
                    title: "quota.weekly".localized(fallback: "每周"),
                    remainingPercent: weeklyRemainingPercent,
                    resetTime: weeklyResetTime,
                    tint: weeklyRemainingPercent > 50 ? Color.semanticSuccess : (weeklyRemainingPercent > 20 ? Color.semanticWarning : Color.semanticDanger)
                )
            }
        }
    }
    
    private var sessionRemainingPercent: Double {
        guard !accounts.isEmpty else { return 100 }
        let readyCount = accounts.filter { $0.status == "ready" && !$0.disabled }.count
        return Double(readyCount) / Double(accounts.count) * 100
    }
    
    private var weeklyRemainingPercent: Double {
        100 - min(100, Double(errorCount) / Double(max(accounts.count, 1)) * 100 + (100 - sessionRemainingPercent) * 0.3)
    }
    
    private var sessionResetTime: String {
        if let coolingAccount = accounts.first(where: { $0.status == "cooling" }),
           let message = coolingAccount.humanReadableStatus,
           let minutes = QuotaCardTimeParser.parseMinutes(from: message) {
            return minutes >= 60
                ? "quota.time.hours".localized(fallback: "\(minutes / 60)小时")
                : "quota.time.minutes".localized(fallback: "\(minutes)分钟")
        }
        return coolingCount > 0 ? "quota.time.approxHour".localized(fallback: "约1小时") : "—"
    }
    
    private var weeklyResetTime: String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilMonday = (9 - weekday) % 7
        return daysUntilMonday == 0
            ? "quota.time.today".localized(fallback: "今天")
            : "quota.time.days".localized(fallback: "\(daysUntilMonday)天")
    }
    
    // MARK: - Status Breakdown
    
    private var statusBreakdownSection: some View {
        HStack(spacing: 16) {
            StatusBadge(count: readyCount, label: "quota.health.ready".localized(fallback: "可用"), color: .semanticSuccess)
            StatusBadge(count: coolingCount, label: "quota.health.cooling".localized(fallback: "冷却中"), color: .semanticWarning)
            StatusBadge(count: errorCount, label: "quota.health.error".localized(fallback: "错误"), color: .semanticDanger)
        }
        .font(.caption)
    }
    
    // MARK: - Account List
    
    private var accountListSection: some View {
        DisclosureGroup {
            VStack(spacing: 4) {
                ForEach(accounts) { account in
                    QuotaAccountRow(account: account, quotaData: quotaData?[account.quotaLookupKey])
                }
            }
        } label: {
            Text("quota.accounts".localized(fallback: "账号列表"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum QuotaCardTimeParser {
    static func parseMinutes(from message: String) -> Int? {
        let pattern = #"(\d+)\s*(minutes?|mins?\.?|minute|min|hours?|hrs?\.?|hour|hr|h|m|分鐘|分钟|分|小時|小时|时|時|鐘頭|钟头|鐘|钟)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let matches = regex.matches(in: message, range: NSRange(message.startIndex..., in: message))
        guard !matches.isEmpty else { return nil }

        var totalMinutes = 0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: message),
                  let unitRange = Range(match.range(at: 2), in: message),
                  let number = Int(message[numberRange]) else {
                continue
            }
            let unit = String(message[unitRange]).lowercased()
            if unit.hasPrefix("h") || unit.contains("小") || unit.contains("时") || unit.contains("時") || unit.contains("钟头") || unit.contains("鐘頭") {
                totalMinutes += number * 60
            } else {
                totalMinutes += number
            }
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }
}

// MARK: - Quota Section

private struct QuotaSection: View {
    let title: String
    let remainingPercent: Double
    let resetTime: String
    let tint: Color
    
    @State private var settings = MenuBarSettingsManager.shared
    
    private var progressWidth: Double {
        remainingPercent / 100
    }

    private var semanticTint: Color {
        switch remainingPercent {
        case ..<10:
            return .semanticDanger
        case ..<30:
            return .semanticWarning
        case ..<50:
            return .semanticAccentSecondary
        default:
            return tint
        }
    }
    
    var body: some View {
        let displayMode = settings.quotaDisplayMode
        let displayPercent = displayMode.displayValue(from: remainingPercent)
        
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text(verbatim: "\(Int(displayPercent))% \(displayMode.suffixKey.localized())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if resetTime != "—" {
                        Text("•")
                            .foregroundStyle(.quaternary)
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("quota.resetIn".localized(fallback: "重置 \(resetTime)"))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(semanticTint)
                        .frame(width: proxy.size.width * min(1, progressWidth))
                        .motionAwareAnimation(QuotioMotion.contentSwap, value: progressWidth)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(displayPercent))%")
    }
}

// MARK: - Supporting Views

private struct StatusBadge: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: count > 0 ? "circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(color)
            Text(verbatim: "\(count) \(label)")
                .foregroundStyle(count > 0 ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuotaAccountRow: View {
    let account: AuthFile
    var quotaData: ProviderQuotaData?
    @State private var settings = MenuBarSettingsManager.shared

    private var displayName: String {
        let name = account.email ?? account.name
        return name.masked(if: settings.hideSensitiveInfo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(account.statusColor)
                    .frame(width: 8, height: 8)

                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                if let quotaData = quotaData, !quotaData.models.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(quotaData.models.prefix(2)) { model in
                            Text(verbatim: "\(model.percentage)%")
                                .font(.caption2)
                                .foregroundStyle(model.percentage > 50 ? Color.semanticSuccess : (model.percentage > 20 ? Color.semanticWarning : Color.semanticDanger))
                        }
                    }
                } else if let statusMessage = account.humanReadableStatus {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(account.status.capitalized)
                        .font(.caption)
                        .foregroundStyle(account.statusColor)
                }
            }

            // Show token expiry for Kiro accounts
            if let quotaData = quotaData, let tokenExpiry = quotaData.formattedTokenExpiry {
                HStack(spacing: 4) {
                    Image(systemName: "key")
                        .font(.caption2)
                    Text(tokenExpiry)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let mockAccounts = [
        AuthFile(
            id: "1",
            name: "[email protected]",
            provider: "antigravity",
            label: nil,
            status: "ready",
            statusMessage: nil,
            disabled: false,
            unavailable: false,
            runtimeOnly: false,
            source: "file",
            path: nil,
            email: "[email protected]",
            accountType: nil,
            account: nil,
            authIndex: nil,
            createdAt: nil,
            updatedAt: nil,
            lastRefresh: nil
        )
    ]
    
    let mockQuota: [String: ProviderQuotaData] = [
        "[email protected]": ProviderQuotaData(
            models: [
                ModelQuota(name: "gemini-3-pro-high", percentage: 65.0, resetTime: "2025-12-25T00:00:00Z"),
                ModelQuota(name: "gemini-3-flash", percentage: 80.0, resetTime: "2025-12-25T00:00:00Z"),
                ModelQuota(name: "claude-sonnet-4-5-thinking", percentage: 45.0, resetTime: "2025-12-25T00:00:00Z")
            ]
        )
    ]
    
    QuotaCard(provider: .antigravity, accounts: mockAccounts, quotaData: mockQuota)
        .frame(width: 400)
        .padding()
}
