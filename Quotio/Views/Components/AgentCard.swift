//
//  AgentCard.swift
//  Quotio - Individual CLI agent card component
//

import SwiftUI

struct AgentCard: View {
    let status: AgentStatus
    let onConfigure: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Agent Icon
            ZStack {
                Circle()
                    .fill(status.agent.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: status.agent.systemIcon)
                    .font(.title2)
                    .foregroundStyle(status.agent.color)
            }
            
            // Agent Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.agent.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    StatusBadge(status: status)
                }
                
                Text(status.agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                if let path = status.binaryPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if let docsURL = status.agent.docsURL {
                    Link(destination: docsURL) {
                        Image(systemName: "book")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .help("agents.viewDocs".localized())
                    .accessibilityLabel("agents.viewDocs".localized())
                }
                
                Button {
                    onConfigure()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: status.configured ? "arrow.triangle.2.circlepath" : "gearshape")
                        Text(status.configured ? "agents.reconfigure".localized() : "agents.configure".localized())
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(status.agent.color)
                .motionAwareAnimation(QuotioMotion.contentSwap, value: status.configured)
            }
        }
        .padding(16)
        .background(isHovered ? Color.semanticSurfaceMuted : Color.semanticSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovered
                    ? status.agent.color.opacity(status.configured ? 0.45 : 0.22)
                    : (status.configured ? status.agent.color.opacity(0.3) : Color.clear),
                    lineWidth: isHovered ? 1.3 : 1
                )
        )
        .shadow(color: isHovered ? status.agent.color.opacity(0.08) : .clear, radius: isHovered ? 8 : 0, y: isHovered ? 2 : 0)
        .onHover { hovering in
            withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .motionAwareAnimation(QuotioMotion.hover, value: isHovered)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: status.configured)
        .quotioHoverFeedback(scale: 1.005, opacity: 1)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: AgentStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.statusColor)
                .frame(width: 6, height: 6)
            
            Text(status.statusText)
                .font(.caption)
                .foregroundStyle(status.statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.statusColor.opacity(0.1))
        .clipShape(Capsule())
        .motionAwareAnimation(QuotioMotion.contentSwap, value: status.statusText)
    }
}

#Preview {
    VStack(spacing: 16) {
        AgentCard(
            status: AgentStatus(
                agent: .claudeCode,
                installed: true,
                configured: true,
                binaryPath: "/usr/local/bin/claude",
                version: "1.0.0",
                lastConfigured: Date()
            ),
            onConfigure: {}
        )
        
        AgentCard(
            status: AgentStatus(
                agent: .geminiCLI,
                installed: true,
                configured: false,
                binaryPath: "/opt/homebrew/bin/gemini",
                version: nil,
                lastConfigured: nil
            ),
            onConfigure: {}
        )
        
        AgentCard(
            status: AgentStatus(
                agent: .openCode,
                installed: true,
                configured: false,
                binaryPath: nil,
                version: nil,
                lastConfigured: nil
            ),
            onConfigure: {}
        )
    }
    .padding()
    .frame(width: 600)
}
