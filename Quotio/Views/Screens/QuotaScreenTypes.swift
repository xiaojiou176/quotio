//
//  QuotaScreenTypes.swift
//  Quotio
//

import SwiftUI

// MARK: - Sort Option

enum AccountSortOption: String, CaseIterable, Identifiable {
    case name = "name"
    case status = "status"
    case quotaLow = "quotaLow"
    case quotaHigh = "quotaHigh"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "quota.sort.name".localized(fallback: "按名称")
        case .status: return "quota.sort.status".localized(fallback: "按状态")
        case .quotaLow: return "quota.sort.quotaLow".localized(fallback: "额度低→高")
        case .quotaHigh: return "quota.sort.quotaHigh".localized(fallback: "额度高→低")
        }
    }
    
    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .status: return "circle.grid.2x1"
        case .quotaLow: return "arrow.up.right"
        case .quotaHigh: return "arrow.down.right"
        }
    }
}

enum AccountStatusFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case ready = "ready"
    case cooling = "cooling"
    case error = "error"
    case disabled = "disabled"
    case quota5h = "quota5h"
    case quota7d = "quota7d"
    case fatalDisabled = "fatalDisabled"
    case networkError = "networkError"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "logs.all".localized(fallback: "全部")
        case .ready: return "quota.status.ready".localized(fallback: "可用")
        case .cooling: return "quota.status.cooling".localized(fallback: "冷却中")
        case .error: return "quota.status.error".localized(fallback: "错误")
        case .disabled: return "quota.status.disabled".localized(fallback: "禁用")
        case .quota5h: return "quota.status.quota5h".localized(fallback: "5h 冷却")
        case .quota7d: return "quota.status.quota7d".localized(fallback: "7d 冷却")
        case .fatalDisabled: return "quota.status.fatalDisabled".localized(fallback: "致命禁用")
        case .networkError: return "quota.status.networkError".localized(fallback: "网络抖动")
        }
    }

    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .ready: return "checkmark.circle.fill"
        case .cooling: return "clock.badge.exclamationmark"
        case .error: return "xmark.circle.fill"
        case .disabled: return "minus.circle.fill"
        case .quota5h: return "clock.arrow.circlepath"
        case .quota7d: return "calendar.badge.clock"
        case .fatalDisabled: return "exclamationmark.octagon.fill"
        case .networkError: return "wifi.exclamationmark"
        }
    }
}

enum CodexRoutingBucket: String, CaseIterable, Identifiable {
    case main
    case fatalDisabled
    case tokenInvalidated
    case quota5h
    case quota7d

    var id: String { rawValue }

    var label: String {
        switch self {
        case .main:
            return "codex.bucket.main".localized(fallback: "可用")
        case .fatalDisabled:
            return "codex.bucket.fatalDisabled".localized(fallback: "致命错误")
        case .tokenInvalidated:
            return "codex.bucket.tokenInvalidated".localized(fallback: "需重登")
        case .quota5h:
            return "codex.bucket.quota5h".localized(fallback: "5h 冷却")
        case .quota7d:
            return "codex.bucket.quota7d".localized(fallback: "7d 冷却")
        }
    }

    var color: Color {
        switch self {
        case .main: return Color.semanticSuccess
        case .fatalDisabled: return Color.semanticDanger
        case .tokenInvalidated: return Color.semanticDanger
        case .quota5h: return Color.semanticWarning
        case .quota7d: return Color.semanticAccentSecondary
        }
    }
}

struct QuotaDisplayHelper {
    let displayMode: QuotaDisplayMode
    
    func statusTint(remainingPercent: Double) -> Color {
        let clamped = max(0, min(100, remainingPercent))
        let usedPercent = 100 - clamped
        let checkValue = displayMode == .used ? usedPercent : clamped
        
        if displayMode == .used {
            if checkValue < 70 { return Color.semanticSuccess }
            if checkValue < 90 { return Color.semanticWarning }
            return Color.semanticDanger
        }
        
        if checkValue > 50 { return Color.semanticSuccess }
        if checkValue > 20 { return Color.semanticWarning }
        return Color.semanticDanger
    }
    
    func displayPercent(remainingPercent: Double) -> Double {
        let clamped = max(0, min(100, remainingPercent))
        return displayMode == .used ? (100 - clamped) : clamped
    }
}

// MARK: - QuotaScreen Data Source Extension

extension QuotaScreen {
    /// All providers with quota data (unified from both proxy and direct sources)
    var availableProviders: [AIProvider] {
        var providers = Set<AIProvider>()

        // From proxy auth files
        for file in viewModel.authFiles {
            if let provider = file.providerType {
                providers.insert(provider)
            }
        }

        // From direct quota data
        for provider in viewModel.providerQuotas.keys {
            providers.insert(provider)
        }

        let sorted = providers.sorted { $0.displayName < $1.displayName }
        guard featureFlags.enhancedUILayout, prioritizeAnomalies else { return sorted }
        return sorted.sorted { lhs, rhs in
            let lhsSeverity = providerSeverity(lhs)
            let rhsSeverity = providerSeverity(rhs)
            if lhsSeverity != rhsSeverity {
                return lhsSeverity > rhsSeverity
            }
            return lhs.displayName < rhs.displayName
        }
    }

    func providerSeverity(_ provider: AIProvider) -> Int {
        let accountQuotas = viewModel.providerQuotas[provider] ?? [:]
        let errorCount = accountQuotas.values.filter { $0.isForbidden }.count
        let lowQuotaCount = accountQuotas.values.filter { quota in
            let models = quota.models.map { (name: $0.name, percentage: $0.percentage) }
            let percent = settings.totalUsagePercent(models: models)
            return percent >= 0 && percent < 20
        }.count
        return errorCount * 5 + lowQuotaCount * 2 + max(0, accountCount(for: provider) / 10)
    }

    /// Get account count for a provider
    func accountCount(for provider: AIProvider) -> Int {
        // Prefer auth files as source-of-truth when available.
        // Some fetchers (notably Codex) intentionally expose multiple alias keys
        // for the same account in providerQuotas, which can inflate raw key counts.
        var authIdentities = Set<String>()
        for file in viewModel.authFiles where file.providerType == provider {
            let candidates = [file.email, file.quotaLookupKey, file.name]
            for candidate in candidates {
                guard let candidate else { continue }
                let identity = normalizedAccountIdentity(candidate)
                if !identity.isEmpty {
                    authIdentities.insert(identity)
                }
            }
        }
        if !authIdentities.isEmpty {
            return authIdentities.count
        }

        // Fallback for providers without auth files (e.g., some auto-detected/CLI-only flows).
        var quotaIdentities = Set<String>()
        if let quotaAccounts = viewModel.providerQuotas[provider] {
            for key in quotaAccounts.keys {
                let identity = normalizedAccountIdentity(key)
                if !identity.isEmpty {
                    quotaIdentities.insert(identity)
                }
            }
        }
        return quotaIdentities.count
    }

    private func normalizedAccountIdentity(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let (cleanName, _) = AccountInfo.extractCleanDisplayName(from: trimmed, email: nil)
        return cleanName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func lowestQuotaPercent(for provider: AIProvider) -> Double? {
        guard let accounts = viewModel.providerQuotas[provider] else { return nil }

        var allTotals: [Double] = []
        for (_, quotaData) in accounts {
            let models = quotaData.models.map { (name: $0.name, percentage: $0.percentage) }
            let total = settings.totalUsagePercent(models: models)
            if total >= 0 {
                allTotals.append(total)
            }
        }

        return allTotals.min()
    }

    /// Check if we have any data to show
    var hasAnyData: Bool {
        if modeManager.isMonitorMode {
            return !viewModel.providerQuotas.isEmpty || !viewModel.directAuthFiles.isEmpty
        }
        return !viewModel.authFiles.isEmpty || !viewModel.providerQuotas.isEmpty
    }
}
