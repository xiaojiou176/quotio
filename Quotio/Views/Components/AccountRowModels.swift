//
//  AccountRowModels.swift
//  Quotio
//
//  Shared model types for account row rendering.
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
        if let email = email, !email.isEmpty, !email.contains("-team"), !email.hasSuffix(".json") {
            return (email, rawName.lowercased().contains("-team"))
        }

        var name = rawName
        let isTeam = name.lowercased().contains("-team")

        if name.hasSuffix(".json") {
            name = String(name.dropLast(5))
        }

        if name.lowercased().hasSuffix("-team") {
            name = String(name.dropLast(5))
        }

        if let atRange = name.range(of: "@") {
            let beforeAt = name[..<atRange.lowerBound]
            var emailStart = beforeAt.startIndex
            if let lastHyphen = beforeAt.lastIndex(of: "-") {
                emailStart = beforeAt.index(after: lastHyphen)
            }

            let afterAt = name[atRange.upperBound...]
            var emailEnd = afterAt.endIndex
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

    var menuBarItem: MenuBarQuotaItem {
        MenuBarQuotaItem(provider: provider.rawValue, accountKey: menuBarAccountKey)
    }

    // MARK: - Factory Methods

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
