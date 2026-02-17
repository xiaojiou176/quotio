//
//  LogsScreenRows.swift
//  Quotio
//

import SwiftUI
import AppKit

extension LogsScreen {
    enum LogsTab: String, CaseIterable {
        case requests = "requests"
        case proxyLogs = "proxyLogs"

        var title: String {
            switch self {
            case .requests: return "logs.tab.requests".localizedStatic()
            case .proxyLogs: return "logs.tab.proxyLogs".localizedStatic()
            }
        }

        var icon: String {
            switch self {
            case .requests: return "arrow.up.arrow.down"
            case .proxyLogs: return "doc.text"
            }
        }
    }

    enum RequestStatusFilter: String, CaseIterable, Identifiable {
        case all
        case success
        case clientError
        case serverError

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "logs.all".localized(fallback: "全部")
            case .success: return "status.connected".localized(fallback: "成功")
            case .clientError: return "logs.clientError".localized(fallback: "客户端错误")
            case .serverError: return "logs.serverError".localized(fallback: "服务端错误")
            }
        }
    }

    enum ProxyLogViewMode: String, CaseIterable, Identifiable {
        case structured
        case raw

        var id: String { rawValue }

        var title: String {
            switch self {
            case .structured:
                return "logs.proxyView.structured".localized(fallback: "结构化")
            case .raw:
                return "logs.proxyView.raw".localized(fallback: "原始")
            }
        }
    }

    enum ProxyLogsContentState {
        case loading
        case error(String)
        case empty
        case success
    }
}

struct RequestRow: View {
    let request: RequestLog
    let evidence: RequestHistoryItem?
    let authEvidence: AuthFile?
    let isTraceExpanded: Bool
    let isPayloadExpanded: Bool
    let onToggleTrace: () -> Void
    let onTogglePayload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                // Timestamp
                Text(request.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                // Status Badge
                statusBadge

                // Provider & Model with Fallback Route
                VStack(alignment: .leading, spacing: 2) {
                    if request.hasFallbackRoute {
                        // Show fallback route: virtual model → resolved model
                        HStack(spacing: 4) {
                            Text(request.model ?? "logs.status.unknown".localized(fallback: "未知"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.semanticWarning)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(request.resolvedProvider?.capitalized ?? "")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.semanticInfo)
                        }
                        Text(request.resolvedModel ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        // Normal display
                        if let provider = request.provider {
                            Text(provider.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        if let model = request.model {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        if let source = request.source ?? evidence?.source {
                            Label(source, systemImage: "app.badge")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let account = request.accountHint ?? evidence?.authIndex {
                            Label(account, systemImage: "person.text.rectangle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let kind = authEvidence?.normalizedErrorKind, !kind.isEmpty {
                            Label(kind, systemImage: "exclamationmark.bubble")
                                .font(.caption2)
                                .foregroundStyle(Color.semanticWarning)
                                .lineLimit(1)
                        }
                    }

                    if let frozenUntil = authEvidence?.frozenUntilDate, frozenUntil > Date() {
                        Label(
                            String(
                                format: "logs.auth.frozenUntil".localized(fallback: "冻结至 %@"),
                                frozenUntil.formatted(date: .omitted, time: .shortened)
                            ),
                            systemImage: "clock.badge.exclamationmark"
                        )
                            .font(.caption2)
                            .foregroundStyle(Color.semanticWarning)
                    }

                    if authEvidence?.isFatalDisabled == true {
                        Label("logs.auth.fatalDisabled".localized(fallback: "致命禁用"), systemImage: "exclamationmark.octagon.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.semanticDanger)
                    }
                }
                .frame(width: 180, alignment: .leading)

                // Tokens
                if let tokens = request.formattedTokens {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.caption2)
                        Text(tokens)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .trailing)
                }

                // Duration
                Text(request.formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Spacer()

                // Size
                HStack(spacing: 4) {
                    Text("\(request.requestSize.formatted())B")
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(request.responseSize.formatted())B")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption2, design: .monospaced))

                if let rid = request.shortRequestId ?? evidence?.requestId.map({ String($0.prefix(8)) }) {
                    Text("#" + rid)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            if let attempts = request.fallbackAttempts, !attempts.isEmpty {
                Button {
                    onToggleTrace()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isTraceExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("logs.fallbackTrace".localized())
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isTraceExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(attempts.enumerated()), id: \.offset) { index, attempt in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)

                                Text("\(attempt.provider) → \(attempt.modelId)")
                                    .font(.caption2)
                                    .lineLimit(1)

                                Text(attemptOutcomeLabel(attempt.outcome))
                                    .font(.caption2)
                                    .foregroundStyle(attemptOutcomeTint(attempt.outcome))

                                if let reason = attempt.reason {
                                    Text(reason.displayValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let errorMessage = request.errorMessage, !errorMessage.isEmpty {
                            HStack(spacing: 6) {
                                Text("logs.fallbackBackendResponse".localized())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
            }

            if request.requestPayloadSnippet != nil || request.sourceRaw != nil {
                Button {
                    onTogglePayload()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPayloadExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("logs.payloadEvidence".localized(fallback: "请求证据"))
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isPayloadExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        if let sourceRaw = request.sourceRaw {
                            HStack(alignment: .top, spacing: 6) {
                                Text("logs.sourceRaw".localized(fallback: "原始来源:"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(sourceRaw)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }

                        if let payload = request.requestPayloadSnippet {
                            Text(payload)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("logs.payloadRedactedNote".localized(fallback: "已自动脱敏并截断，完整请求体不默认长期保留。"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("logs.requestRow".localized(fallback: "请求日志行"))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusSymbol)
                .font(.caption2)
            Text(request.statusBadge)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
        }
        .foregroundStyle(Color.semanticOnAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(statusColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("logs.status".localized(fallback: "状态"))
        .accessibilityValue(statusDescription + " \(request.statusBadge)")
    }

    private var statusColor: Color {
        guard let code = request.statusCode else { return .secondary }
        switch code {
        case 200..<300: return Color.semanticSuccess
        case 400..<500: return Color.semanticWarning
        case 500..<600: return Color.semanticDanger
        default: return .secondary
        }
    }

    private var statusSymbol: String {
        guard let code = request.statusCode else { return "questionmark.circle" }
        switch code {
        case 200..<300: return "checkmark.circle.fill"
        case 400..<500: return "exclamationmark.triangle.fill"
        case 500..<600: return "xmark.octagon.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusDescription: String {
        guard let code = request.statusCode else { return "logs.status.unknown".localized(fallback: "未知") }
        switch code {
        case 200..<300: return "logs.status.success".localized(fallback: "成功")
        case 400..<500: return "logs.status.clientError".localized(fallback: "客户端错误")
        case 500..<600: return "logs.status.serverError".localized(fallback: "服务端错误")
        default: return "logs.status.unknown".localized(fallback: "未知")
        }
    }

    private func attemptOutcomeLabel(_ outcome: FallbackAttemptOutcome) -> String {
        switch outcome {
        case .failed:
            return "logs.fallbackAttempt.failed".localized()
        case .success:
            return "logs.fallbackAttempt.success".localized()
        case .skipped:
            return "logs.fallbackAttempt.skipped".localized()
        }
    }

    private func attemptOutcomeTint(_ outcome: FallbackAttemptOutcome) -> Color {
        switch outcome {
        case .failed:
            return Color.semanticWarning
        case .success:
            return Color.semanticSuccess
        case .skipped:
            return .secondary
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
    }
}

// MARK: - Log Row

struct LogRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp, style: .time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Text(entry.level.rawValue.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(Color.semanticOnAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(entry.level.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("logs.proxyLogRow".localized(fallback: "代理日志行"))
        .accessibilityValue("\(entry.level.rawValue) \(entry.message)")
    }
}

struct StructuredLogRow: View {
    let entry: LogEntry

    private var parsed: ParsedProxyLogEntry {
        ParsedProxyLogEntry.parse(entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(entry.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(entry.level.rawValue.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.semanticOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(entry.level.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(parsed.source)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 135, alignment: .leading)

                if let method = parsed.method {
                    Text(method)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(method == "GET" ? Color.semanticInfo : Color.semanticAccentSecondary)
                        .frame(width: 44, alignment: .leading)
                }

                Text(parsed.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let status = parsed.statusCode {
                    Text(String(status))
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(status >= 500 ? Color.semanticDanger : (status >= 400 ? Color.semanticWarning : Color.semanticSuccess))
                        .frame(width: 38, alignment: .trailing)
                }

                if let duration = parsed.duration {
                    Text(duration)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }

            if let detail = parsed.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.leading, 64)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ParsedProxyLogEntry {
    let source: String
    let method: String?
    let path: String
    let statusCode: Int?
    let duration: String?
    let detail: String?

    static func parse(_ entry: LogEntry) -> ParsedProxyLogEntry {
        let message = entry.message
        let source = extractSource(from: message) ?? "runtime"
        let core = message.components(separatedBy: " - ").last ?? message

        // Example: GET /v1/chat/completions 200 1.3ms
        let pattern = #"(GET|POST|PUT|PATCH|DELETE)\s+(\S+)\s+(\d{3})\s+([0-9]+(?:\.[0-9]+)?(?:ms|s))"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: core, range: NSRange(core.startIndex..., in: core)),
           let methodRange = Range(match.range(at: 1), in: core),
           let pathRange = Range(match.range(at: 2), in: core),
           let statusRange = Range(match.range(at: 3), in: core),
           let durationRange = Range(match.range(at: 4), in: core) {
            let method = String(core[methodRange])
            let path = String(core[pathRange])
            let status = Int(core[statusRange])
            let duration = String(core[durationRange])
            return ParsedProxyLogEntry(
                source: source,
                method: method,
                path: path,
                statusCode: status,
                duration: duration,
                detail: core
            )
        }

        return ParsedProxyLogEntry(
            source: source,
            method: nil,
            path: core,
            statusCode: nil,
            duration: nil,
            detail: nil
        )
    }

    private static func extractSource(from message: String) -> String? {
        // Example: gin_logger.go:93
        let pattern = #"([A-Za-z0-9_\-\.]+\.go:\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return String(message[range])
    }
}
