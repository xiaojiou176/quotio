//
//  QuotaScreenProviderComponents.swift
//  Quotio
//

import SwiftUI

struct ProviderSegmentButton: View {
    let provider: AIProvider
    let quotaPercent: Double?
    let accountCount: Int
    let isSelected: Bool
    let action: () -> Void

    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }

    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var statusColor: Color {
        guard let percent = quotaPercent else { return .secondary }
        return displayHelper.statusTint(remainingPercent: percent)
    }
    
    private var remainingPercent: Double {
        max(0, min(100, quotaPercent ?? 0))
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ProviderIcon(provider: provider, size: 20)
                
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                
                if accountCount > 1 {
                    Text(String(accountCount))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? Color.semanticOnAccent : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isSelected ? statusColor : Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                
                if quotaPercent != nil {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: remainingPercent / 100)
                            .stroke(statusColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(statusColor.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .motionAwareAnimation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Quota Status Dot

struct QuotaStatusDot: View {
    let usedPercent: Double
    let size: CGFloat
    
    private var color: Color {
        if usedPercent < 70 { return Color.semanticSuccess }   // <70% used = healthy
        if usedPercent < 90 { return Color.semanticWarning }  // 70-90% used = warning
        return Color.semanticDanger                             // >90% used = critical
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Provider Quota View

struct ProviderQuotaView: View {
    let provider: AIProvider
    let authFiles: [AuthFile]
    let quotaData: [String: ProviderQuotaData]
    let subscriptionInfos: [String: SubscriptionInfo]
    let isLoading: Bool
    var searchFilter: String = ""
    var sortOption: AccountSortOption = .name
    var statusFilter: AccountStatusFilter = .all
    var compactMode: Bool = false
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }

    private func codexDerivedLookupKeys(from fileName: String) -> [String] {
        guard fileName.hasPrefix("codex-"), fileName.hasSuffix(".json") else {
            return []
        }
        var keys: [String] = []
        let stripped = fileName
            .replacingOccurrences(of: "codex-", with: "")
            .replacingOccurrences(of: ".json", with: "")
        if !stripped.isEmpty {
            keys.append(stripped)
            if stripped.hasSuffix("-team") {
                keys.append(String(stripped.dropLast("-team".count)))
            }
            if let atIndex = stripped.firstIndex(of: "@"),
               let hyphenBeforeAt = stripped[..<atIndex].lastIndex(of: "-") {
                let emailCandidate = String(stripped[stripped.index(after: hyphenBeforeAt)...])
                if !emailCandidate.isEmpty {
                    keys.append(emailCandidate)
                    if emailCandidate.hasSuffix("-team") {
                        keys.append(String(emailCandidate.dropLast("-team".count)))
                    }
                }
            }
        }
        return Array(Set(keys))
    }

    private func normalizedIdentity(from rawValue: String) -> String {
        let (cleanName, _) = AccountInfo.extractCleanDisplayName(from: rawValue, email: nil)
        return cleanName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func mergeAccount(_ current: AccountInfo, _ incoming: AccountInfo) -> AccountInfo {
        func score(_ account: AccountInfo) -> Int {
            var value = 0
            if account.authFile != nil { value += 100 }
            if account.quotaData != nil { value += 10 }
            if account.authFile?.isFatalDisabled == true { value += 20 }
            if account.status == "ready" || account.status == "active" { value += 5 }
            if account.authFile?.disabled == true { value -= 5 }
            return value
        }
        return score(incoming) > score(current) ? incoming : current
    }
    
    /// Get all accounts (from auth files or quota data keys)
    private var allAccounts: [AccountInfo] {
        var accountsByIdentity: [String: AccountInfo] = [:]
        var consumedQuotaKeys = Set<String>()

        // From auth files (primary source)
        for file in authFiles {
            let key = file.quotaLookupKey
            let rawEmail = file.email ?? file.name
            let (cleanName, isTeam) = AccountInfo.extractCleanDisplayName(from: rawEmail, email: file.email)

            // Try to find quota data with various possible keys
            let possibleKeys = Array(Set([key, cleanName, rawEmail, file.name] + codexDerivedLookupKeys(from: file.name)))
            let matchedQuotaKey = possibleKeys.first(where: { quotaData[$0] != nil })
            if let matchedQuotaKey {
                consumedQuotaKeys.insert(matchedQuotaKey)
            }
            let matchedQuota = matchedQuotaKey.flatMap { quotaData[$0] }
            let matchedSubscription = possibleKeys.compactMap { subscriptionInfos[$0] }.first

            let account = AccountInfo(
                key: key,
                email: rawEmail,
                displayName: cleanName,
                isTeamAccount: isTeam,
                status: file.status,
                statusColor: file.statusColor,
                authFile: file,
                quotaData: matchedQuota,
                subscriptionInfo: matchedSubscription
            )

            let identity = normalizedIdentity(from: cleanName)
            if let existing = accountsByIdentity[identity] {
                accountsByIdentity[identity] = mergeAccount(existing, account)
            } else {
                accountsByIdentity[identity] = account
            }
        }

        // From quota data (only if not already matched to proxy auth files)
        for (key, data) in quotaData {
            if consumedQuotaKeys.contains(key) {
                continue
            }
            let (cleanName, isTeam) = AccountInfo.extractCleanDisplayName(from: key, email: nil)
            let identity = normalizedIdentity(from: cleanName)
            guard accountsByIdentity[identity] == nil else { continue }

            accountsByIdentity[identity] = AccountInfo(
                key: key,
                email: key,
                displayName: cleanName,
                isTeamAccount: isTeam,
                status: "active",
                statusColor: Color.semanticSuccess,
                authFile: nil,
                quotaData: data,
                subscriptionInfo: subscriptionInfos[key]
            )
        }
        
        // Apply search filter
        var filtered = Array(accountsByIdentity.values)
        if !searchFilter.isEmpty {
            let query = searchFilter.lowercased()
            filtered = filtered.filter { account in
                account.displayName.lowercased().contains(query) ||
                account.email.lowercased().contains(query) ||
                account.key.lowercased().contains(query)
            }
        }

        if statusFilter != .all {
            filtered = filtered.filter { account in
                matchesStatusFilter(account: account)
            }
        }
        
        // Apply sorting
        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .name:
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .status:
                // Sort order: ready/active first, then cooling, then error, then other
                let statusOrder = ["ready": 0, "active": 0, "cooling": 1, "error": 2]
                let lhsOrder = statusOrder[lhs.status] ?? 3
                let rhsOrder = statusOrder[rhs.status] ?? 3
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaLow:
                // Sort by lowest quota percentage first
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota {
                    return lhsQuota < rhsQuota
                }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaHigh:
                // Sort by highest quota percentage first
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota {
                    return lhsQuota > rhsQuota
                }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            }
        }
    }
    
    /// Get the lowest quota percentage for an account
    private func getLowestQuotaPercent(for account: AccountInfo) -> Double {
        guard let data = account.quotaData else { return 100 }
        let models = data.models.map { (name: $0.name, percentage: $0.percentage) }
        let total = settings.totalUsagePercent(models: models)
        return total >= 0 ? total : 100
    }

    private func matchesStatusFilter(account: AccountInfo) -> Bool {
        if provider == .codex {
            let bucket = codexBucket(for: account)
            switch statusFilter {
            case .all:
                return true
            case .ready:
                return bucket == .main
            case .cooling:
                return bucket == .quota5h || bucket == .quota7d
            case .error:
                return bucket == .fatalDisabled || bucket == .tokenInvalidated
            case .disabled:
                return account.authFile?.disabled == true
            case .quota5h:
                return bucket == .quota5h
            case .quota7d:
                return bucket == .quota7d
            case .fatalDisabled:
                return bucket == .fatalDisabled
            case .networkError:
                return account.authFile?.isNetworkError == true
            }
        }

        switch statusFilter {
        case .all:
            return true
        case .ready:
            return account.status == "ready" || account.status == "active"
        case .cooling:
            return account.status == "cooling"
        case .error:
            return account.status == "error"
        case .disabled:
            return account.authFile?.disabled == true
        case .quota5h:
            return account.authFile?.isQuotaLimited5h == true
        case .quota7d:
            return account.authFile?.isQuotaLimited7d == true
        case .fatalDisabled:
            return account.authFile?.isFatalDisabled == true
        case .networkError:
            return account.authFile?.isNetworkError == true
        }
    }

    private func codexBucket(for account: AccountInfo) -> CodexRoutingBucket {
        if account.authFile?.isFatalDisabled == true {
            return .fatalDisabled
        }
        if account.authFile?.isQuotaLimited7d == true {
            return .quota7d
        }
        if account.authFile?.isQuotaLimited5h == true {
            return .quota5h
        }
        let statusText = account.status.lowercased()
        let errorKind = account.authFile?.normalizedErrorKind ?? ""
        let statusMessage = account.authFile?.statusMessage?.lowercased() ?? ""
        if errorKind == "workspace_deactivated" || statusMessage.contains("workspace_deactivated") {
            return .fatalDisabled
        }
        if errorKind == "quota_limited_7d"
            || errorKind == "quota_limited_7days"
            || statusMessage.contains("quota_limited_7d")
            || statusMessage.contains("quota_limited_7days") {
            return .quota7d
        }
        if errorKind == "quota_limited_5h" || statusMessage.contains("quota_limited_5h") {
            return .quota5h
        }
        if statusText == "error" ||
            statusText == "invalid" ||
            statusMessage.contains("invalid") ||
            statusMessage.contains("unauthorized") ||
            statusMessage.contains("token") {
            return .tokenInvalidated
        }

        let sessionRemaining = codexRemainingPercent(for: account, modelName: "codex-session")
        let weeklyRemaining = codexRemainingPercent(for: account, modelName: "codex-weekly")

        if weeklyRemaining <= 0.1 {
            return .quota7d
        }
        if sessionRemaining <= 0.1 {
            return .quota5h
        }
        return .main
    }

    private func codexRemainingPercent(for account: AccountInfo, modelName: String) -> Double {
        account.quotaData?.models.first(where: { $0.name == modelName })?.percentage ?? 100
    }

    private func codexResetDate(for account: AccountInfo, modelName: String) -> Date? {
        guard let resetString = account.quotaData?.models.first(where: { $0.name == modelName })?.resetTime,
              !resetString.isEmpty else {
            return nil
        }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterDefault = ISO8601DateFormatter()
        formatterDefault.formatOptions = [.withInternetDateTime]
        return formatterWithFractional.date(from: resetString) ?? formatterDefault.date(from: resetString)
    }

    private func codexSorted(_ accounts: [AccountInfo], in bucket: CodexRoutingBucket) -> [AccountInfo] {
        accounts.sorted { lhs, rhs in
            switch sortOption {
            case .name:
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaLow:
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota { return lhsQuota < rhsQuota }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .quotaHigh:
                let lhsQuota = getLowestQuotaPercent(for: lhs)
                let rhsQuota = getLowestQuotaPercent(for: rhs)
                if lhsQuota != rhsQuota { return lhsQuota > rhsQuota }
                return lhs.displayName.lowercased() < rhs.displayName.lowercased()
            case .status:
                break
            }

            switch bucket {
            case .main:
                let lhsWeekly = codexRemainingPercent(for: lhs, modelName: "codex-weekly")
                let rhsWeekly = codexRemainingPercent(for: rhs, modelName: "codex-weekly")
                if lhsWeekly != rhsWeekly { return lhsWeekly > rhsWeekly }

                let lhsSession = codexRemainingPercent(for: lhs, modelName: "codex-session")
                let rhsSession = codexRemainingPercent(for: rhs, modelName: "codex-session")
                if lhsSession != rhsSession { return lhsSession > rhsSession }

            case .quota5h:
                let lhsReset = codexResetDate(for: lhs, modelName: "codex-session") ?? .distantFuture
                let rhsReset = codexResetDate(for: rhs, modelName: "codex-session") ?? .distantFuture
                if lhsReset != rhsReset { return lhsReset < rhsReset }

            case .quota7d:
                let lhsReset = codexResetDate(for: lhs, modelName: "codex-weekly") ?? .distantFuture
                let rhsReset = codexResetDate(for: rhs, modelName: "codex-weekly") ?? .distantFuture
                if lhsReset != rhsReset { return lhsReset < rhsReset }

            case .fatalDisabled:
                let lhsStatus = lhs.authFile?.statusMessage ?? lhs.status
                let rhsStatus = rhs.authFile?.statusMessage ?? rhs.status
                if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }

            case .tokenInvalidated:
                let lhsStatus = lhs.authFile?.statusMessage ?? lhs.status
                let rhsStatus = rhs.authFile?.statusMessage ?? rhs.status
                if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
            }

            return lhs.displayName.lowercased() < rhs.displayName.lowercased()
        }
    }
    
    /// Group accounts by status for organized display
    private var accountsByStatus: [(status: String, label: String, color: Color, accounts: [AccountInfo])] {
        let all = allAccounts
        
        var ready: [AccountInfo] = []
        var cooling: [AccountInfo] = []
        var error: [AccountInfo] = []
        var other: [AccountInfo] = []
        
        for account in all {
            switch account.status {
            case "ready", "active":
                ready.append(account)
            case "cooling":
                cooling.append(account)
            case "error":
                error.append(account)
            default:
                other.append(account)
            }
        }
        
        var groups: [(status: String, label: String, color: Color, accounts: [AccountInfo])] = []
        
        if !ready.isEmpty {
            groups.append(("ready", "quota.status.ready".localized(fallback: "可用"), Color.semanticSuccess, ready))
        }
        if !cooling.isEmpty {
            groups.append(("cooling", "quota.status.cooling".localized(fallback: "冷却中"), Color.semanticWarning, cooling))
        }
        if !error.isEmpty {
            groups.append(("error", "quota.status.error".localized(fallback: "错误"), Color.semanticDanger, error))
        }
        if !other.isEmpty {
            groups.append(("other", "quota.status.other".localized(fallback: "其他"), .secondary, other))
        }
        
        return groups
    }

    private var codexAccountsByBucket: [(bucket: CodexRoutingBucket, accounts: [AccountInfo])] {
        let accounts = allAccounts
        var grouped: [CodexRoutingBucket: [AccountInfo]] = [
            .main: [],
            .fatalDisabled: [],
            .tokenInvalidated: [],
            .quota5h: [],
            .quota7d: []
        ]

        for account in accounts {
            grouped[codexBucket(for: account), default: []].append(account)
        }

        let orderedBuckets: [CodexRoutingBucket] = [.main, .quota5h, .quota7d, .fatalDisabled, .tokenInvalidated]
        return orderedBuckets.compactMap { bucket in
            let list = grouped[bucket] ?? []
            guard !list.isEmpty else { return nil }
            return (bucket, codexSorted(list, in: bucket))
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if allAccounts.isEmpty && isLoading {
                QuotaLoadingView()
            } else if allAccounts.isEmpty {
                emptyState
            } else if provider == .codex {
                ForEach(codexAccountsByBucket, id: \.bucket.rawValue) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(group.bucket.color)
                                .frame(width: 8, height: 8)
                            Text(group.bucket.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text("(\(group.accounts.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.top, group.bucket == .main ? 0 : 8)

                        ForEach(group.accounts, id: \.key) { account in
                            accountView(account)
                        }
                    }
                }
            } else if allAccounts.count <= 3 {
                // For small number of accounts, show flat list
                ForEach(allAccounts, id: \.key) { account in
                    accountView(account)
                }
            } else {
                // For larger number of accounts, group by status
                ForEach(accountsByStatus, id: \.status) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        // Group header
                        HStack(spacing: 6) {
                            Circle()
                                .fill(group.color)
                                .frame(width: 8, height: 8)
                            Text(group.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Text("(\(group.accounts.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.top, group.status == "ready" ? 0 : 8)
                        
                        // Account cards
                        ForEach(group.accounts, id: \.key) { account in
                            accountView(account)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountView(_ account: AccountInfo) -> some View {
        if compactMode && account.authFile?.isFatalDisabled != true {
            CompactAccountQuotaRow(provider: provider, account: account)
        } else {
            AccountQuotaCardV2(
                provider: provider,
                account: account,
                isLoading: isLoading && account.quotaData == nil
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("quota.noDataYet".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

struct CompactAccountQuotaRow: View {
    let provider: AIProvider
    let account: AccountInfo

    private var lowestQuotaPercent: Double {
        guard let quota = account.quotaData else { return -1 }
        let models = quota.models.map { (name: $0.name, percentage: $0.percentage) }
        return MenuBarSettingsManager.shared.totalUsagePercent(models: models)
    }

    private var quotaText: String {
        if lowestQuotaPercent < 0 {
            return "—"
        }
        return "\(Int(lowestQuotaPercent))%"
    }

    private var quotaColor: Color {
        switch lowestQuotaPercent {
        case ..<0:
            return .secondary
        case ..<10:
            return Color.semanticDanger
        case ..<30:
            return Color.semanticWarning
        case ..<50:
            return Color.semanticWarning
        default:
            return Color.semanticSuccess
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ProviderIcon(provider: provider, size: 14)

            Text(account.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let status = account.authFile?.status {
                Text(status.localizedCapitalized)
                    .font(.caption2)
                    .foregroundStyle(account.statusColor)
            }

            Text(quotaText)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(quotaColor)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Account Info

struct AccountInfo {
    let key: String
    let email: String           // Original email/name for technical operations
    let displayName: String     // Clean display name (extracted email)
    let isTeamAccount: Bool     // Whether this is a team account
    let status: String
    let statusColor: Color
    let authFile: AuthFile?
    let quotaData: ProviderQuotaData?
    
    /// Extract a clean display name from technical account identifiers
    static func extractCleanDisplayName(from rawName: String, email: String?) -> (displayName: String, isTeam: Bool) {
        // If we have a clean email, use it
        if let email = email, !email.isEmpty, !email.contains("-team"), !email.hasSuffix(".json") {
            return (email, rawName.lowercased().contains("-team"))
        }
        
        var name = rawName
        let isTeam = name.lowercased().contains("-team")
        
        // Remove .json suffix
        if name.hasSuffix(".json") {
            name = String(name.dropLast(5))
        }
        
        // Remove -team suffix
        if name.lowercased().hasSuffix("-team") {
            name = String(name.dropLast(5))
        }
        
        // Find email pattern (something with @ in it)
        if let atRange = name.range(of: "@") {
            // Find the start of the email (after the last hyphen before @)
            let beforeAt = name[..<atRange.lowerBound]
            var emailStart = beforeAt.startIndex
            if let lastHyphen = beforeAt.lastIndex(of: "-") {
                emailStart = beforeAt.index(after: lastHyphen)
            }
            
            // Find the end of the email domain
            let afterAt = name[atRange.upperBound...]
            var emailEnd = afterAt.endIndex
            
            // Check for common patterns that indicate end of domain
            for pattern in ["-gmail", "-manager", "-project", "-cli"] {
                if let patternRange = afterAt.range(of: pattern, options: .caseInsensitive) {
                    emailEnd = patternRange.lowerBound
                    break
                }
            }
            
            let extractedEmail = name[emailStart..<emailEnd]
            if extractedEmail.contains("@") && extractedEmail.count > 3 {
                return (String(extractedEmail), isTeam)
            }
        }
        
        return (name, isTeam)
    }
    
    let subscriptionInfo: SubscriptionInfo?
}

// MARK: - Account Quota Card V2
