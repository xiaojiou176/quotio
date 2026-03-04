//
//  UsageStatsScreenComponents.swift
//  Quotio
//

import SwiftUI

enum UsageStatsColumnWidth {
    static let status: CGFloat = 28
    static let timeMin: CGFloat = 60
    static let timeIdeal: CGFloat = 76
    static let modelMin: CGFloat = 104
    static let accountMin: CGFloat = 92
    static let sourceMin: CGFloat = 76
    static let requestIdMin: CGFloat = 60
    static let requestIdIdeal: CGFloat = 96
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Spacer()
                }
                
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RequestHistoryRow: View {
    let item: RequestHistoryItem
    var onFocus: (() -> Void)? = nil
    @State private var copyFeedbackState: CopyFeedbackState = .idle

    private enum CopyFeedbackState: Equatable {
        case idle
        case busy
        case success
        case failure
    }

    private var accessibilitySummary: String {
        let status = item.success
            ? "status.connected".localized(fallback: "成功")
            : "status.error".localized(fallback: "失败")
        let timeText = item.date.map { date in
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        } ?? "usage.stats.header.time".localized(fallback: "时间未知")
        let model = item.model ?? "logs.status.unknown".localized(fallback: "未知")
        let source = item.source ?? "usage.stats.header.source".localized(fallback: "来源未知")
        return "stats.requestRow.a11y.label".localized(
            fallback: "请求 \(status)，时间 \(timeText)，模型 \(model)，来源 \(source)"
        )
    }

    private var accessibilityDetail: String {
        var parts: [String] = []
        if let authIndex = item.authIndex, !authIndex.isEmpty {
            parts.append("usage.stats.header.account".localized(fallback: "账号") + " \(authIndex)")
        }
        if let tokens = item.tokens {
            parts.append("stats.requestRow.a11y.tokens".localized(fallback: "Token \(tokens)"))
        }
        if let requestId = item.requestId, !requestId.isEmpty {
            parts.append("stats.requestRow.a11y.requestId".localized(fallback: "请求 ID \(requestId)"))
        }
        return parts.joined(separator: "，")
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Button {
                onFocus?()
            } label: {
                HStack(spacing: 12) {
                    // Status indicator
                    Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(item.success ? Color.semanticSuccess : Color.semanticDanger)
                        .frame(width: UsageStatsColumnWidth.status, alignment: .leading)

                    // Time
                    if let date = item.date {
                        Text(date, style: .time)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(
                                minWidth: UsageStatsColumnWidth.timeMin,
                                idealWidth: UsageStatsColumnWidth.timeIdeal,
                                maxWidth: UsageStatsColumnWidth.timeIdeal,
                                alignment: .leading
                            )
                    }

                    // Model
                    Text(item.model ?? "logs.status.unknown".localized(fallback: "未知"))
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: UsageStatsColumnWidth.modelMin, alignment: .leading)
                        .layoutPriority(2)

                    // Account
                    if let authIndex = item.authIndex {
                        Text(authIndex)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: UsageStatsColumnWidth.accountMin, alignment: .leading)
                            .layoutPriority(1)
                    }

                    // Source
                    if let source = item.source {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: UsageStatsColumnWidth.sourceMin, alignment: .leading)
                            .layoutPriority(1)
                    }

                    Spacer()

                    // Tokens
                    if let tokens = item.tokens {
                        Text("\(tokens)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if item.requestId != nil {
                        Text("#" + String((item.requestId ?? "").prefix(8)))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(
                                minWidth: UsageStatsColumnWidth.requestIdMin,
                                idealWidth: UsageStatsColumnWidth.requestIdIdeal,
                                maxWidth: UsageStatsColumnWidth.requestIdIdeal,
                                alignment: .trailing
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onFocus == nil)
            .help("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
            .accessibilityLabel(accessibilitySummary)
            .accessibilityValue(accessibilityDetail)
            .accessibilityHint("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
            .focusable(true)
            .quotioHoverFeedback()
            .motionAwareAnimation(QuotioMotion.press, value: onFocus == nil)
            .motionAwareAnimation(QuotioMotion.contentSwap, value: item.success)

            if item.requestId != nil {
                Button {
                    guard let requestId = item.requestId else { return }
                    copyFeedbackState = .busy
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    if pasteboard.setString(requestId, forType: .string) {
                        copyFeedbackState = .success
                    } else {
                        copyFeedbackState = .failure
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copyFeedbackState = .idle
                    }
                } label: {
                    Image(systemName: copyFeedbackIconName)
                        .font(.caption2)
                        .foregroundStyle(copyFeedbackTint)
                        .scaleEffect(copyFeedbackState == .success ? 1.08 : 1)
                }
                .buttonStyle(.subtle)
                .help("stats.requestId.copy.help".localized(fallback: "复制请求 ID"))
                .accessibilityLabel("stats.requestId.copy".localized(fallback: "复制请求 ID"))
                .accessibilityValue(copyAccessibilityValue)
                .motionAwareAnimation(QuotioMotion.contentSwap, value: copyFeedbackState)
            }
        }
        .padding(.vertical, 4)
    }

    private var copyFeedbackIconName: String {
        switch copyFeedbackState {
        case .idle:
            return "doc.on.doc"
        case .busy:
            return "clock"
        case .success:
            return "checkmark"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var copyFeedbackTint: Color {
        switch copyFeedbackState {
        case .idle:
            return .secondary
        case .busy:
            return Color.semanticInfo
        case .success:
            return Color.semanticSuccess
        case .failure:
            return Color.semanticDanger
        }
    }

    private var copyAccessibilityValue: String {
        switch copyFeedbackState {
        case .idle:
            return "status.idle".localized(fallback: "待复制")
        case .busy:
            return "status.loading".localized(fallback: "处理中")
        case .success:
            return "status.success".localized(fallback: "复制成功")
        case .failure:
            return "status.error".localized(fallback: "复制失败")
        }
    }
}

struct AccountStatsCard: View {
    let account: String
    let stats: APIUsageSnapshot
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(Color.semanticInfo)
                    Text(account)
                        .font(.headline)
                    Spacer()
                    Text("\(stats.totalRequests ?? 0) "+"stats.requests".localized(fallback: "请求"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                if let models = stats.models, !models.isEmpty {
                    ForEach(models.sorted(by: { ($0.value.totalRequests ?? 0) > ($1.value.totalRequests ?? 0) }), id: \.key) { model, modelStats in
                        HStack {
                            Text(model)
                                .font(.caption)
                            Spacer()
                            Text("\(modelStats.totalRequests ?? 0) "+"stats.req".localized(fallback: "次"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\((modelStats.totalTokens ?? 0).formattedTokenCount)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.semanticAccentSecondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct ModelStatItem {
    let model: String
    let requests: Int
    let tokens: Int
}

struct ModelStatsCard: View {
    let stat: ModelStatItem
    
    var body: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.model)
                        .font(.headline)
                    Text("\(stat.requests) "+"stats.requests".localized(fallback: "请求"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(stat.tokens.formattedTokenCount)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.semanticAccentSecondary)
                    Text("usage.stats.tokens.unit".localized(fallback: "tokens"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct SSEEventRow: View {
    let event: SSERequestEvent
    var onFocus: (() -> Void)? = nil

    private var accessibilitySummary: String {
        let model = event.model ?? "logs.status.unknown".localized(fallback: "未知")
        let source = event.source ?? "usage.stats.header.source".localized(fallback: "来源未知")
        let result = event.success == true
            ? "status.connected".localized(fallback: "成功")
            : "status.error".localized(fallback: "失败")
        return "stats.realtimeRow.a11y.label".localized(
            fallback: "实时事件 \(event.type)，结果 \(result)，模型 \(model)，来源 \(source)"
        )
    }

    private var accessibilityDetail: String {
        var parts: [String] = []
        if let authFile = event.authFile {
            parts.append("stats.realtimeRow.a11y.account".localized(fallback: "账号 \(authFile)"))
        }
        if let requestId = event.requestId, !requestId.isEmpty {
            parts.append("stats.realtimeRow.a11y.requestId".localized(fallback: "请求 ID \(requestId)"))
        }
        return parts.joined(separator: "，")
    }
    
    var body: some View {
        Button {
            onFocus?()
        } label: {
            HStack(spacing: 12) {
                // Event type indicator
                Image(systemName: eventIcon)
                    .foregroundStyle(eventColor)
                
                // Time
                if let date = event.date {
                    Text(date, style: .time)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                // Model
                if let model = event.model {
                    Text(model)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                // Account
                if let authFile = event.authFile {
                    Text(authFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let source = event.source {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status badge
                Text(event.type.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.semanticOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(eventColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onFocus == nil)
        .help("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
        .accessibilityLabel(accessibilitySummary)
        .accessibilityValue(accessibilityDetail)
        .accessibilityHint("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
        .quotioHoverFeedback()
        .motionAwareAnimation(QuotioMotion.contentSwap, value: event.success)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: event.type)
    }
    
    private var eventIcon: String {
        switch event.type {
        case "request": return "arrow.up.arrow.down"
        case "quota_exceeded": return "exclamationmark.triangle.fill"
        case "error": return "xmark.circle.fill"
        case "connected": return "checkmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    private var eventColor: Color {
        switch event.type {
        case "request": return event.success == true ? Color.semanticSuccess : Color.semanticWarning
        case "quota_exceeded": return Color.semanticWarning
        case "error": return Color.semanticDanger
        case "connected": return Color.semanticInfo
        default: return .gray
        }
    }
}

#Preview {
    UsageStatsScreen()
}
