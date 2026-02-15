//
//  AccountRow.swift
//  Quotio
//
//  Unified account row component for ProvidersScreen.
//  Replaces: AuthFileRow, DirectAuthFileRow, AutoDetectedAccountRow
//

import SwiftUI

/// Represents the source/type of an account for display purposes
enum AccountSource: Equatable {
    case proxy           // From proxy API (AuthFile)
    case direct          // From disk auth files (DirectAuthFile)
    case autoDetected    // Auto-detected from IDE (Cursor, Trae)
    
    var displayName: String {
        switch self {
        case .proxy: return "providers.source.proxy".localizedStatic()
        case .direct: return "providers.source.disk".localizedStatic()
        case .autoDetected: return "providers.autoDetected".localizedStatic()
        }
    }
}

/// Unified data model for account display
struct AccountRowData: Identifiable, Hashable {
    let id: String
    let provider: AIProvider
    let displayName: String       // Email or account identifier (cleaned up for display)
    let rawName: String           // Original name for technical operations
    let menuBarAccountKey: String
    let source: AccountSource
    let status: String?           // "ready", "cooling", "error", etc.
    let statusMessage: String?
    let errorKind: String?
    let errorReason: String?
    let frozenUntil: Date?
    let disabledByPolicy: Bool
    let isDisabled: Bool
    let canDelete: Bool           // Only proxy accounts can be deleted
    let canEdit: Bool             // Whether this account can be edited (GLM only)
    let canSwitch: Bool           // Whether this account can be switched (Antigravity only)
    let isTeamAccount: Bool       // Whether this is a team account (for badge display)

    // Custom initializer to handle canEdit parameter
    init(
        id: String,
        provider: AIProvider,
        displayName: String,
        rawName: String? = nil,
        menuBarAccountKey: String? = nil,
        source: AccountSource,
        status: String?,
        statusMessage: String?,
        errorKind: String? = nil,
        errorReason: String? = nil,
        frozenUntil: Date? = nil,
        disabledByPolicy: Bool = false,
        isDisabled: Bool,
        canDelete: Bool,
        canEdit: Bool = false,
        canSwitch: Bool = false,
        isTeamAccount: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.rawName = rawName ?? displayName
        self.menuBarAccountKey = menuBarAccountKey ?? displayName
        self.source = source
        self.status = status
        self.statusMessage = statusMessage
        self.errorKind = errorKind
        self.errorReason = errorReason
        self.frozenUntil = frozenUntil
        self.disabledByPolicy = disabledByPolicy
        self.isDisabled = isDisabled
        self.canDelete = canDelete
        self.canEdit = canEdit
        self.canSwitch = canSwitch
        self.isTeamAccount = isTeamAccount
    }
    
    // MARK: - Display Name Extraction
    
    /// Extract a clean display name from technical account identifiers
    /// Examples:
    /// - "codex-1d155e15-chatgpt71@xiaojiou176.me-team.json" → "chatgpt71@xiaojiou176.me"
    /// - "antigravity-terry@casium.com.json" → "terry@casium.com"
    /// - "gemini-user@gmail.com-gmail-manager-485502.json" → "user@gmail.com"
    private static func extractCleanDisplayName(from rawName: String, email: String?) -> (displayName: String, isTeam: Bool) {
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
        
        // Try to extract email from patterns like:
        // "codex-1d155e15-chatgpt71@xiaojiou176.me"
        // "antigravity-terry@casium.com"
        // "gemini-user@gmail.com-gmail-manager-485502"
        
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
            // e.g., "-gmail-manager" or just the natural end
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

    // For menu bar selection
    var menuBarItem: MenuBarQuotaItem {
        MenuBarQuotaItem(provider: provider.rawValue, accountKey: menuBarAccountKey)
    }

    // MARK: - Factory Methods
    
    /// Create from AuthFile (proxy mode)
    static func from(authFile: AuthFile) -> AccountRowData {
        let rawName = authFile.email ?? authFile.name
        let (cleanName, isTeam) = extractCleanDisplayName(from: rawName, email: authFile.email)
        return AccountRowData(
            id: authFile.id,
            provider: authFile.providerType ?? .gemini,
            displayName: cleanName,
            rawName: rawName,
            menuBarAccountKey: authFile.menuBarAccountKey,
            source: .proxy,
            status: authFile.status,
            statusMessage: authFile.statusMessage,
            errorKind: authFile.normalizedErrorKind,
            errorReason: authFile.errorReason,
            frozenUntil: authFile.frozenUntilDate,
            disabledByPolicy: authFile.disabledByPolicy ?? false,
            isDisabled: authFile.disabled,
            canDelete: true,
            isTeamAccount: isTeam
        )
    }
    
    /// Create from DirectAuthFile (quota-only mode or proxy stopped)
    static func from(directAuthFile: DirectAuthFile) -> AccountRowData {
        let rawName = directAuthFile.email ?? directAuthFile.filename
        let (cleanName, isTeam) = extractCleanDisplayName(from: rawName, email: directAuthFile.email)
        return AccountRowData(
            id: directAuthFile.id,
            provider: directAuthFile.provider,
            displayName: cleanName,
            rawName: rawName,
            menuBarAccountKey: directAuthFile.menuBarAccountKey,
            source: .direct,
            status: nil,
            statusMessage: nil,
            isDisabled: false,
            canDelete: false,
            isTeamAccount: isTeam
        )
    }
    
    /// Create from auto-detected account (Cursor, Trae)
    static func from(provider: AIProvider, accountKey: String) -> AccountRowData {
        let (cleanName, isTeam) = extractCleanDisplayName(from: accountKey, email: nil)
        return AccountRowData(
            id: "\(provider.rawValue)_\(accountKey)",
            provider: provider,
            displayName: cleanName,
            rawName: accountKey,
            menuBarAccountKey: accountKey,
            source: .autoDetected,
            status: nil,
            statusMessage: nil,
            isDisabled: false,
            canDelete: false,
            isTeamAccount: isTeam
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isDisabled)
        hasher.combine(status)
        hasher.combine(isTeamAccount)
        hasher.combine(errorKind)
        hasher.combine(disabledByPolicy)
    }

    static func == (lhs: AccountRowData, rhs: AccountRowData) -> Bool {
        lhs.id == rhs.id &&
        lhs.isDisabled == rhs.isDisabled &&
        lhs.status == rhs.status &&
        lhs.isTeamAccount == rhs.isTeamAccount &&
        lhs.errorKind == rhs.errorKind &&
        lhs.disabledByPolicy == rhs.disabledByPolicy
    }
}

// MARK: - AccountRow View

struct AccountRow: View {
    let account: AccountRowData
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onSwitch: (() -> Void)?
    var onToggleDisabled: (() -> Void)?
    var isActiveInIDE: Bool = false
    var compactMode: Bool = false
    
    @State private var settings = MenuBarSettingsManager.shared
    @State private var featureFlags = FeatureFlagManager.shared
    @State private var uiExperience = UIExperienceSettingsManager.shared
    @State private var showWarning = false
    @State private var showMaxItemsAlert = false
    @State private var showDeleteConfirmation = false
    
    private var isMenuBarSelected: Bool {
        settings.isSelected(account.menuBarItem)
    }
    
    private var maskedDisplayName: String {
        account.displayName.masked(if: settings.hideSensitiveInfo)
    }
    
    private var statusColor: Color {
        switch account.status {
        case "ready", "active": return account.isDisabled ? .secondary : .semanticSuccess
        case "cooling": return .semanticWarning
        case "error": return .semanticDanger
        default: return .secondary
        }
    }

    private var statusSymbol: String {
        switch account.status {
        case "ready", "active": return account.isDisabled ? "pause.circle.fill" : "checkmark.circle.fill"
        case "cooling": return "clock.badge.exclamationmark"
        case "error": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusDisplayText: String? {
        guard let status = account.status else { return nil }
        switch status {
        case "ready", "active":
            return "quota.status.ready".localized(fallback: "可用")
        case "cooling":
            return "quota.status.cooling".localized(fallback: "冷却中")
        case "error":
            return "quota.status.error".localized(fallback: "错误")
        default:
            return status.localizedCapitalized
        }
    }

    private var normalizedErrorKind: String {
        account.errorKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var normalizedErrorReason: String {
        account.errorReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var requiresRelogin: Bool {
        if normalizedErrorKind == "unauthorized" || normalizedErrorKind == "account_deactivated" {
            return true
        }
        if normalizedErrorReason.contains("token_invalidated") ||
            normalizedErrorReason.contains("token has been invalidated") ||
            normalizedErrorReason.contains("authentication token has been invalidated") {
            return true
        }
        return false
    }

    private var permanentlyInvalid: Bool {
        if normalizedErrorKind == "workspace_deactivated" {
            return true
        }
        if account.disabledByPolicy && (normalizedErrorKind == "workspace_deactivated" || normalizedErrorKind == "account_deactivated") {
            return true
        }
        return false
    }

    private var errorKindDisplayText: String? {
        guard !normalizedErrorKind.isEmpty else { return nil }
        switch normalizedErrorKind {
        case "quota_limited_5h":
            return "account.errorKind.quota5h".localized(fallback: "5h 冷却")
        case "quota_limited_7d":
            return "account.errorKind.quota7d".localized(fallback: "7d 冷却")
        case "quota_limited":
            return "account.errorKind.rateLimited".localized(fallback: "限流")
        case "network_error":
            return "account.errorKind.networkError".localized(fallback: "网络抖动")
        case "workspace_deactivated":
            return "account.errorKind.workspaceDeactivated".localized(fallback: "工作区停用")
        case "account_deactivated":
            return "account.errorKind.accountDeactivated".localized(fallback: "账号停用")
        case "unauthorized":
            return "account.errorKind.unauthorized".localized(fallback: "鉴权失败")
        default:
            return normalizedErrorKind
        }
    }
    
    var body: some View {
        HStack(spacing: compactMode ? 8 : 12) {
            // Provider icon
            ProviderIcon(provider: account.provider, size: compactMode ? 18 : 24)
            
            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(maskedDisplayName)
                    .font(compactMode ? .subheadline : .body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Provider name
                    Text(account.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Status indicator (only for proxy accounts)
                    if let statusText = statusDisplayText {
                        Image(systemName: statusSymbol)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                            .accessibilityHidden(true)

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    } else {
                        // Source indicator for non-proxy accounts
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        Text(account.source.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !compactMode, let reason = account.errorReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Team badge
            if !compactMode, account.isTeamAccount {
                Text("account.badge.team".localized(fallback: "团队"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.semanticAccentSecondary)
                    .clipShape(Capsule())
            }
            
            // Disabled badge
            if account.isDisabled {
                Text("providers.disabled".localized())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }

            if !compactMode, permanentlyInvalid {
                Text("account.status.permanent".localized(fallback: "永久失效"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticDanger)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.semanticDanger.opacity(0.15))
                    .clipShape(Capsule())
            } else if !compactMode, requiresRelogin {
                Text("account.status.relogin".localized(fallback: "需重登"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.semanticWarning.opacity(0.15))
                    .clipShape(Capsule())
            }

            if !compactMode, account.disabledByPolicy {
                Text("account.badge.policy".localized(fallback: "策略禁用"))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticDanger)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.semanticDanger.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !compactMode, let kind = errorKindDisplayText {
                Text(kind)
                    .font(.caption2)
                    .foregroundStyle(Color.semanticWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.semanticWarning.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !compactMode, let frozenUntil = account.frozenUntil, frozenUntil > Date() {
                Text("\("account.badge.until".localized(fallback: "截至")) \(frozenUntil.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Active in IDE badge (Antigravity only)
            if account.provider == .antigravity && isActiveInIDE {
                Text("antigravity.active".localized())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.semanticSuccess)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.semanticSuccess.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            // Switch button (Antigravity only, for proxy/direct accounts that are not active)
            if !compactMode, account.provider == .antigravity && !isActiveInIDE && account.source != .autoDetected {
                Button {
                    onSwitch?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.caption2)
                        Text("antigravity.useInIDE".localized())
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.semanticSelectionFill)
                    .foregroundStyle(Color.semanticInfo)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("antigravity.switch.title".localized())
            }
            
            // Menu bar toggle
            if !compactMode {
                MenuBarBadge(
                    isSelected: isMenuBarSelected,
                    onTap: handleMenuBarToggle
                )
            }

            if featureFlags.enhancedUILayout {
                Menu {
                    if account.provider == .antigravity && !isActiveInIDE && account.source != .autoDetected {
                        Button {
                            onSwitch?()
                        } label: {
                            Label("antigravity.switch.title".localized(), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    if account.source == .proxy, let onToggleDisabled = onToggleDisabled {
                        Button {
                            onToggleDisabled()
                        } label: {
                            if account.isDisabled {
                                Label("providers.enable".localized(), systemImage: "checkmark.circle")
                            } else {
                                Label("providers.disable".localized(), systemImage: "minus.circle")
                            }
                        }
                    }

                    if account.canEdit, let onEdit = onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("action.edit".localized(), systemImage: "pencil")
                        }
                    }

                    if account.canDelete, onDelete != nil {
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("action.delete".localized(), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("action.more".localized(fallback: "更多操作"))
                .accessibilityLabel("action.more".localized(fallback: "更多操作"))
            } else {
                // Disable/Enable toggle button (only for proxy accounts)
                if account.source == .proxy, let onToggleDisabled = onToggleDisabled {
                    Button {
                        onToggleDisabled()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(account.isDisabled ? Color.semanticDanger.opacity(0.1) : Color.clear)
                                .frame(width: 28, height: 28)

                            Image(systemName: account.isDisabled ? "xmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(account.isDisabled ? Color.semanticDanger : .secondary)
                        }
                    }
                    .buttonStyle(.rowAction)
                    .help(account.isDisabled ? "providers.enable".localized() : "providers.disable".localized())
                    .accessibilityLabel(account.isDisabled ? "providers.enable".localized() : "providers.disable".localized())
                }

                // Edit button (GLM only)
                if account.canEdit, let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.semanticInfo)
                    }
                    .buttonStyle(.rowAction)
                    .help("action.edit".localized())
                }

                // Delete button (only for proxy accounts)
                if account.canDelete, onDelete != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.semanticDanger.opacity(0.8))
                    }
                    .buttonStyle(.rowActionDestructive)
                    .help("action.delete".localized())
                }
            }
        }
        .frame(minHeight: uiExperience.recommendedMinimumRowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            // Switch account option (Antigravity only)
            if account.provider == .antigravity && !isActiveInIDE && account.source != .autoDetected {
                Button {
                    onSwitch?()
                } label: {
                    Label("antigravity.switch.title".localized(), systemImage: "arrow.triangle.2.circlepath")
                }
                
                Divider()
            }
            
            // Menu bar toggle
            Button {
                handleMenuBarToggle()
            } label: {
                if isMenuBarSelected {
                    Label("menubar.hideFromMenuBar".localized(), systemImage: "chart.bar")
                } else {
                    Label("menubar.showOnMenuBar".localized(), systemImage: "chart.bar.fill")
                }
            }

            // Disable/Enable toggle (only for proxy accounts)
            if account.source == .proxy, let onToggleDisabled = onToggleDisabled {
                Button {
                    onToggleDisabled()
                } label: {
                    if account.isDisabled {
                        Label("providers.enable".localized(), systemImage: "checkmark.circle")
                    } else {
                        Label("providers.disable".localized(), systemImage: "minus.circle")
                    }
                }
            }

            // Delete option (only for proxy accounts)
            if account.canDelete, onDelete != nil {
                Divider()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("action.delete".localized(), systemImage: "trash")
                }
            }
        }
        .confirmationDialog("providers.deleteConfirm".localized(), isPresented: $showDeleteConfirmation) {
            Button("action.delete".localized(), role: .destructive) {
                onDelete?()
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("providers.deleteMessage".localized())
        }
        .alert("menubar.warning.title".localized(), isPresented: $showWarning) {
            Button("menubar.warning.confirm".localized()) {
                settings.toggleItem(account.menuBarItem)
            }
            Button("menubar.warning.cancel".localized(), role: .cancel) {}
        } message: {
            Text("menubar.warning.message".localized())
        }
        .alert("menubar.maxItems.title".localized(), isPresented: $showMaxItemsAlert) {
            Button("action.ok".localized(), role: .cancel) {}
        } message: {
            Text(String(
                format: "menubar.maxItems.message".localized(),
                settings.menuBarMaxItems
            ))
        }
    }
    
    private func handleMenuBarToggle() {
        if isMenuBarSelected {
            settings.toggleItem(account.menuBarItem)
        } else if settings.isAtMaxItems {
            showMaxItemsAlert = true
        } else if settings.shouldWarnOnAdd {
            showWarning = true
        } else {
            settings.toggleItem(account.menuBarItem)
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        AccountRow(
            account: AccountRowData(
                id: "1",
                provider: .gemini,
                displayName: "user@gmail.com",
                source: .proxy,
                status: "ready",
                statusMessage: nil,
                isDisabled: false,
                canDelete: true
            ),
            onDelete: {}
        )
        
        AccountRow(
            account: AccountRowData(
                id: "2",
                provider: .claude,
                displayName: "work@company.com",
                source: .direct,
                status: nil,
                statusMessage: nil,
                isDisabled: false,
                canDelete: false
            )
        )
        
        AccountRow(
            account: AccountRowData(
                id: "3",
                provider: .cursor,
                displayName: "dev@example.com",
                source: .autoDetected,
                status: nil,
                statusMessage: nil,
                isDisabled: false,
                canDelete: false
            )
        )
    }
}
