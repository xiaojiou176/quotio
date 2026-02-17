//
//  ProvidersScreenOAuthSheet.swift
//  Quotio
//

import SwiftUI
import AppKit

// MARK: - OAuth Sheet

struct OAuthSheet: View {
    @Environment(QuotaViewModel.self) private var viewModel
    let provider: AIProvider
    @Binding var projectId: String
    let onDismiss: () -> Void
    
    @State private var hasStartedAuth = false
    @State private var selectedKiroMethod: AuthCommand = .kiroImport
    
    private var isPolling: Bool {
        viewModel.oauthState?.status == .polling || viewModel.oauthState?.status == .waiting
    }
    
    private var isSuccess: Bool {
        viewModel.oauthState?.status == .success
    }
    
    private var isError: Bool {
        viewModel.oauthState?.status == .error
    }
    
    private var kiroAuthMethods: [AuthCommand] {
        [.kiroImport, .kiroGoogleLogin, .kiroAWSAuthCode, .kiroAWSLogin]
    }

    private var normalizedProjectId: String {
        projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var geminiExistingEmailsForProject: [String] {
        guard provider == .gemini, !normalizedProjectId.isEmpty else { return [] }

        var matchedEmails = Set<String>()

        for file in viewModel.authFiles where file.providerType == .gemini {
            let parsed = Self.parseGeminiAuthIdentity(fileName: file.name, account: file.account)
            guard Self.isGeminiProjectPotentialMatch(existingProject: parsed?.projectId, targetProject: normalizedProjectId) else {
                continue
            }

            let candidate = file.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? parsed?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? file.account?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? file.name
            if !candidate.isEmpty {
                matchedEmails.insert(candidate)
            }
        }

        for file in viewModel.directAuthFiles where file.provider == .gemini {
            let parsed = Self.parseGeminiAuthIdentity(fileName: file.filename, account: nil)
            guard Self.isGeminiProjectPotentialMatch(existingProject: parsed?.projectId, targetProject: normalizedProjectId) else {
                continue
            }

            let candidate = file.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? parsed?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? file.filename
            if !candidate.isEmpty {
                matchedEmails.insert(candidate)
            }
        }

        return matchedEmails.sorted()
    }

    private var geminiOverwriteNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("providers.gemini.tip.identity".localized(), systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !geminiExistingEmailsForProject.isEmpty {
                Text(
                    String(
                        format: "providers.gemini.tip.potentialDuplicate".localized(),
                        normalizedProjectId,
                        geminiExistingEmailsForProject.joined(separator: ", ")
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(Color.semanticWarning)
                Text("providers.gemini.tip.keepBoth".localized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.semanticWarning.opacity(0.08))
        )
    }

    private static func parseGeminiAuthIdentity(fileName: String, account: String?) -> (email: String?, projectId: String?)? {
        let accountParsed = parseGeminiAccountField(account)
        let fileParsed = parseGeminiAuthFileName(fileName)

        let email = accountParsed?.email ?? fileParsed?.email
        let projectId = accountParsed?.projectId ?? fileParsed?.projectId

        if email == nil && projectId == nil {
            return nil
        }
        return (email: email, projectId: projectId)
    }

    private static func parseGeminiAccountField(_ account: String?) -> (email: String?, projectId: String?)? {
        guard let rawAccount = account?.trimmingCharacters(in: .whitespacesAndNewlines), !rawAccount.isEmpty else {
            return nil
        }

        if let openParen = rawAccount.lastIndex(of: "("),
           let closeParen = rawAccount.lastIndex(of: ")"),
           openParen < closeParen {
            let emailPart = String(rawAccount[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
            let projectPart = normalizeGeminiProjectIdentifier(
                String(rawAccount[rawAccount.index(after: openParen)..<closeParen])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if !emailPart.isEmpty || !projectPart.isEmpty {
                return (
                    email: emailPart.isEmpty ? nil : emailPart,
                    projectId: projectPart.isEmpty ? nil : projectPart
                )
            }
        }

        if rawAccount.contains("@") {
            return (email: rawAccount, projectId: nil)
        }

        return nil
    }

    private static func parseGeminiAuthFileName(_ fileName: String) -> (email: String?, projectId: String?)? {
        var normalized = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(".json") {
            normalized = String(normalized.dropLast(".json".count))
        }

        if normalized.hasPrefix("gemini-cli-") {
            normalized = String(normalized.dropFirst("gemini-cli-".count))
        } else if normalized.hasPrefix("gemini-") {
            normalized = String(normalized.dropFirst("gemini-".count))
        } else {
            return nil
        }

        guard !normalized.isEmpty else { return nil }

        let emailProjectPattern = #"^(.+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?:-(.+))?$"#
        if let regex = try? NSRegularExpression(pattern: emailProjectPattern) {
            let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if let match = regex.firstMatch(in: normalized, options: [], range: fullRange) {
                let emailValue: String? = {
                    guard match.range(at: 1).location != NSNotFound,
                          let range = Range(match.range(at: 1), in: normalized) else {
                        return nil
                    }
                    return String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }()
                let projectValue: String? = {
                    guard match.range(at: 2).location != NSNotFound,
                          let range = Range(match.range(at: 2), in: normalized) else {
                        return nil
                    }
                    return normalizeGeminiProjectIdentifier(
                        String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }()
                return (
                    email: emailValue?.isEmpty == false ? emailValue : nil,
                    projectId: projectValue?.isEmpty == false ? projectValue : nil
                )
            }
        }

        guard let separator = normalized.lastIndex(of: "-") else {
            if normalized.contains("@") {
                return (email: normalized, projectId: nil)
            }
            return nil
        }

        let emailPart = String(normalized[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let projectPart = normalizeGeminiProjectIdentifier(
            String(normalized[normalized.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if !emailPart.contains("@") {
            return nil
        }

        return (
            email: emailPart.isEmpty ? nil : emailPart,
            projectId: projectPart.isEmpty ? nil : projectPart
        )
    }

    private static func normalizeGeminiProjectIdentifier(_ raw: String) -> String {
        var project = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return "" }
        if let separator = project.range(of: "--", options: .backwards) {
            let suffix = project[separator.upperBound...]
            let isCredentialSuffix = !suffix.isEmpty && suffix.allSatisfy { $0.isNumber || $0.isLetter }
            if isCredentialSuffix {
                project = String(project[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return project
    }

    private static func isGeminiProjectPotentialMatch(existingProject: String?, targetProject: String) -> Bool {
        let normalizedTarget = targetProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else { return false }

        guard let rawExisting = existingProject?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawExisting.isEmpty else {
            return false
        }

        if rawExisting.caseInsensitiveCompare(normalizedTarget) == .orderedSame {
            return true
        }

        let targetLowercased = normalizedTarget.lowercased()
        let existingLowercased = rawExisting.lowercased()
        if targetLowercased == "all" || existingLowercased == "all" {
            return true
        }

        if rawExisting.contains(",") {
            let projectTokens = rawExisting
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if projectTokens.contains("all") || projectTokens.contains(targetLowercased) {
                return true
            }
        }

        return false
    }
    
    var body: some View {
        VStack(spacing: 28) {
            ProviderIcon(provider: provider, size: 64)
            
            VStack(spacing: 8) {
                Text("oauth.connect".localized() + " " + provider.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("oauth.authenticateWith".localized() + " " + provider.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if provider == .gemini {
                VStack(alignment: .leading, spacing: 6) {
                    Text("oauth.projectId".localized())
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("oauth.projectIdPlaceholder".localized(), text: $projectId)
                        .textFieldStyle(.roundedBorder)

                    geminiOverwriteNotice
                }
                .frame(maxWidth: 320)
            }
            
            if provider == .kiro {
                VStack(alignment: .leading, spacing: 6) {
                    Text("oauth.authMethod".localized())
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker("", selection: $selectedKiroMethod) {
                        ForEach(kiroAuthMethods, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("oauth.authMethod".localized())
                    .help("oauth.authMethod".localized())
                    

                }
                .frame(maxWidth: 320)
            }
            
            if let state = viewModel.oauthState, state.provider == provider {
                OAuthStatusView(status: state.status, error: state.error, state: state.state, authURL: state.authURL, provider: provider)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            HStack(spacing: 16) {
                Button("action.cancel".localized(), role: .cancel) {
                    viewModel.cancelOAuth()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                if isError {
                    Button {
                        hasStartedAuth = false
                        Task {
                            await viewModel.startOAuth(for: provider, projectId: projectId.isEmpty ? nil : projectId, authMethod: provider == .kiro ? selectedKiroMethod : nil)
                        }
                    } label: {
                        Label("oauth.retry".localized(), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.semanticWarning)
                } else if !isSuccess {
                    Button {
                        hasStartedAuth = true
                        Task {
                            await viewModel.startOAuth(for: provider, projectId: projectId.isEmpty ? nil : projectId, authMethod: provider == .kiro ? selectedKiroMethod : nil)
                        }
                    } label: {
                        if isPolling {
                            SmallProgressView()
                        } else {
                            Label("oauth.authenticate".localized(), systemImage: "key.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(provider.color)
                    .disabled(isPolling)
                }
            }
        }
        .padding(32)
        .frame(width: 480)
        .frame(minHeight: 350)
        .fixedSize(horizontal: false, vertical: true)
        .motionAwareAnimation(.easeInOut(duration: 0.2), value: viewModel.oauthState?.status)
        .onChange(of: viewModel.oauthState?.status) { _, newStatus in
            if newStatus == .success {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    onDismiss()
                }
            }
        }
    }
}

private struct OAuthStatusView: View {
    let status: OAuthState.OAuthStatus
    let error: String?
    let state: String?
    let authURL: String?
    let provider: AIProvider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// Stable rotation angle for spinner animation (fixes UUID() infinite re-render)
    @State private var rotationAngle: Double = 0

    private func restartPollingSpinner() {
        rotationAngle = 0
        guard !reduceMotion else { return }
        withMotionAwareAnimation(.linear(duration: 1).repeatForever(autoreverses: false), reduceMotion: reduceMotion) {
            rotationAngle = 360
        }
    }
    
    /// Visual feedback for copy action
    @State private var copied = false
    
    var body: some View {
        Group {
            switch status {
            case .waiting:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("oauth.openingBrowser".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                
            case .polling:
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(provider.color.opacity(0.2), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(provider.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(rotationAngle - 90))
                            .onAppear {
                                restartPollingSpinner()
                            }
                            .onDisappear {
                                rotationAngle = 0
                            }
                            .onChange(of: reduceMotion) { _, _ in
                                restartPollingSpinner()
                            }
                        
                        Image(systemName: "person.badge.key.fill")
                            .font(.title2)
                            .foregroundStyle(provider.color)
                    }
                    
                    // For Copilot Device Code flow, show device code with copy button
                    if provider == .copilot, let deviceCode = state, !deviceCode.isEmpty {
                        VStack(spacing: 8) {
                            Text("oauth.enterCodeInBrowser".localized())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                Text(deviceCode)
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(provider.color)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(provider.color.opacity(0.1))
                                    .cornerRadius(8)
                                
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(deviceCode, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.title3)
                                }
                                .buttonStyle(.subtle)
                                .help("action.copyCode".localized())
                                .accessibilityLabel("action.copyCode".localized())
                            }
                            
                            Text("oauth.waitingForAuth".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if provider == .copilot, let message = error {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 350)
                    } else {
                        Text("oauth.waitingForAuth".localized())
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // Show auth URL with copy/open buttons
                        if let urlString = authURL, let url = URL(string: urlString) {
                            VStack(spacing: 12) {
                                Text("oauth.copyLinkOrOpen".localized())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(urlString, forType: .string)
                                        copied = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            copied = false
                                        }
                                    } label: {
                                        Label(copied ? "oauth.copied".localized() : "oauth.copyLink".localized(), systemImage: copied ? "checkmark" : "doc.on.doc")
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label("oauth.openLink".localized(), systemImage: "safari")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(provider.color)
                                }
                            }
                        } else {
                            Text("oauth.completeBrowser".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 16)
                
            case .success:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.semanticSuccess)
                    
                    Text("oauth.success".localized())
                        .font(.headline)
                        .foregroundStyle(Color.semanticSuccess)
                    
                    Text("oauth.closingSheet".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                
            case .error:
                VStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.semanticDanger)
                    
                    Text("oauth.failed".localized())
                        .font(.headline)
                        .foregroundStyle(Color.semanticDanger)
                    
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .frame(minHeight: 100)
    }
}
