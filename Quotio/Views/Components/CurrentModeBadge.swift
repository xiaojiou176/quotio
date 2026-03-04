//
//  CurrentModeBadge.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//
//  Compact badge showing current operating mode in sidebar footer
//

import SwiftUI

/// Compact badge showing current mode in sidebar, clickable to open settings
struct CurrentModeBadge: View {
    @Environment(QuotaViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modeManager = OperatingModeManager.shared
    @State private var isHovered = false
    @GestureState private var isPressed = false
    
    var body: some View {
        Button {
            viewModel.currentPage = .settings
        } label: {
            HStack(spacing: 8) {
                // Mode icon
                Image(systemName: modeManager.currentMode.icon)
                    .font(.caption)
                    .foregroundStyle(modeManager.currentMode.color)
                
                // Mode name
                VStack(alignment: .leading, spacing: 1) {
                    Text(modeName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    // Status subtitle
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(shouldEmphasizeHealthyState && !reduceMotion ? 1.01 : 1)
            .quotioPressFeedback(isPressed: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
        .help("sidebar.modeBadge.hint".localized())
        .motionAwareAnimation(QuotioMotion.hover, value: isHovered)
        .motionAwareAnimation(QuotioMotion.press, value: isPressed)
        .motionAwareAnimation(QuotioMotion.contentSwap, value: modeStatusAnimationKey)
        .motionAwareAnimation(QuotioMotion.successEmphasis, value: shouldEmphasizeHealthyState)
    }
    
    private var modeName: String {
        switch modeManager.currentMode {
        case .monitor:
            return "mode.monitor".localized()
        case .localProxy:
            return "mode.localProxy".localized()
        case .remoteProxy:
            return "mode.remoteProxy".localized()
        }
    }
    
    private var statusText: String {
        switch modeManager.currentMode {
        case .monitor:
            let count = viewModel.directAuthFiles.count
            return String(format: "sidebar.modeBadge.accounts".localized(), count)
        case .localProxy:
            if viewModel.proxyManager.proxyStatus.running {
                return ":" + String(viewModel.proxyManager.port) + " - " + "status.running".localized()
            } else {
                return "status.stopped".localized()
            }
        case .remoteProxy:
            switch modeManager.connectionStatus {
            case .connected:
                return "status.connected".localized()
            case .connecting:
                return "status.connecting".localized()
            case .disconnected:
                return "status.disconnected".localized()
            case .error:
                return "status.error".localized()
            }
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        if isHovered {
            modeManager.currentMode.color.opacity(0.08)
        } else {
            Color.clear
        }
    }
    
    private var borderColor: Color {
        if isHovered {
            return modeManager.currentMode.color.opacity(0.3)
        } else {
            return Color.secondary.opacity(0.15)
        }
    }

    private var shouldEmphasizeHealthyState: Bool {
        switch modeManager.currentMode {
        case .monitor:
            return !viewModel.directAuthFiles.isEmpty
        case .localProxy:
            return viewModel.proxyManager.proxyStatus.running
        case .remoteProxy:
            return modeManager.connectionStatus == .connected
        }
    }

    private var modeStatusAnimationKey: String {
        "\(modeManager.currentMode)-\(statusText)"
    }
}

#Preview {
    CurrentModeBadge()
        .environment(QuotaViewModel())
        .padding()
        .frame(width: 200)
}
