//
//  UsageStatsScreenComponents.swift
//  Quotio
//

import SwiftUI

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
    @State private var copied = false
    
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

                    // Time
                    if let date = item.date {
                        Text(date, style: .time)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                    }

                    // Model
                    Text(item.model ?? "logs.status.unknown".localized(fallback: "未知"))
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)

                    // Account
                    if let authIndex = item.authIndex {
                        Text(authIndex)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                    }

                    // Source
                    if let source = item.source {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)
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
                            .frame(width: 76, alignment: .trailing)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onFocus == nil)
            .help("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
            .accessibilityLabel("stats.requestHistoryRow".localized(fallback: "请求历史行"))
            .accessibilityHint("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
            .focusable(true)

            if item.requestId != nil {
                Button {
                    guard let requestId = item.requestId else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(requestId, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(copied ? Color.semanticSuccess : .secondary)
                }
                .buttonStyle(.borderless)
                .help("stats.requestId.copy.help".localized(fallback: "复制请求 ID"))
                .accessibilityLabel("stats.requestId.copy".localized(fallback: "复制请求 ID"))
            }
        }
        .padding(.vertical, 4)
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
        .accessibilityLabel("stats.realtimeEventRow".localized(fallback: "实时事件行"))
        .accessibilityHint("stats.focusLog".localized(fallback: "点击在日志中聚焦此请求"))
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
