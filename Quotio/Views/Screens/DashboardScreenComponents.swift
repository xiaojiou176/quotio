//
//  DashboardScreenComponents.swift
//  Quotio
//

import SwiftUI

struct GettingStartedStep: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let isCompleted: Bool
    let actionLabel: String?
}

struct GettingStartedStepRow: View {
    let step: GettingStartedStep
    let onAction: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(step.isCompleted ? Color.semanticSuccess : Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                if step.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.semanticOnAccent)
                } else {
                    Image(systemName: step.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(step.title)
                        .font(.headline)
                    
                    if step.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticSuccess)
                            .font(.caption)
                    }
                }
                
                Text(step.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let actionLabel = step.actionLabel {
                Button(actionLabel) {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - KPI Card

struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Provider Chip

struct ProviderChip: View {
    let provider: AIProvider
    let count: Int
    
    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: provider, size: 16)
            Text(provider.displayName)
            if count > 1 {
                Text("×\(count)")
                    .fontWeight(.semibold)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(provider.color.opacity(0.15))
        .foregroundStyle(provider.color)
        .clipShape(Capsule())
    }
}

// MARK: - Provider Chip With Add Button (for connected providers)

struct ProviderChipWithAdd: View {
    let provider: AIProvider
    let count: Int
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: provider, size: 16)
            Text(provider.displayName)
            if count > 0 {
                Text("×\(count)")
                    .fontWeight(.semibold)
            }
            // Show "+" icon on hover or always show a subtle indicator
            Image(systemName: "plus.circle.fill")
                .font(.caption2)
                .foregroundStyle(isHovering ? provider.color : provider.color.opacity(0.5))
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(provider.color.opacity(isHovering ? 0.25 : 0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(provider.color.opacity(isHovering ? 0.5 : 0), lineWidth: 1)
        )
        .foregroundStyle(provider.color)
        .onHover { hovering in
            withMotionAwareAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Quota Provider Row (for Quota-Only Mode Dashboard)

struct QuotaProviderRow: View {
    let provider: AIProvider
    let accounts: [String: ProviderQuotaData]
    
    private var lowestQuota: Double {
        accounts.values.flatMap { $0.models }.map { $0.percentage }.min() ?? 100
    }
    
    private var quotaColor: Color {
        if lowestQuota > 50 { return Color.semanticSuccess }
        if lowestQuota > 20 { return Color.semanticWarning }
        return Color.semanticDanger
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ProviderIcon(provider: provider, size: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(accounts.count) " + "quota.accounts".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Lowest quota indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(quotaColor)
                    .frame(width: 8, height: 8)
                
                Text(String(format: "%.0f%%", lowestQuota))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(quotaColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(quotaColor.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Network Sections

struct DashboardEndpointSection: View {
    let endpoint: String

    var body: some View {
        GroupBox {
            HStack {
                Text(endpoint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(endpoint, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("action.copy".localized())
                .help("action.copy".localized())
            }
        } label: {
            Label("dashboard.apiEndpoint".localized(), systemImage: "link")
        }
    }
}

struct DashboardTunnelSection: View {
    let tunnelManager: TunnelManager
    @Binding var showTunnelSheet: Bool

    var body: some View {
        GroupBox {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.semanticInfo.opacity(0.15), Color.semanticAccentSecondary.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                        )

                    Image(systemName: "globe")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.semanticInfo, Color.semanticAccentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.semanticInfo.opacity(0.3), radius: 4, x: 0, y: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("tunnel.section.title".localized())
                            .font(.headline)

                        TunnelStatusBadge(status: tunnelManager.tunnelState.status, compact: true)
                    }

                    if tunnelManager.tunnelState.isActive, let url = tunnelManager.tunnelState.publicURL {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospaced()
                    } else {
                        Text("tunnel.section.description".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if tunnelManager.tunnelState.isActive {
                    Button {
                        tunnelManager.copyURLToClipboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("action.copy".localized())
                    .help("action.copy".localized())
                }

                Button {
                    showTunnelSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("settings.config".localized())
                .help("settings.config".localized())
            }
        } label: {
            Label("tunnel.section.label".localized(), systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
