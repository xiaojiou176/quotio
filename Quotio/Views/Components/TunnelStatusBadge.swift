//
//  TunnelStatusBadge.swift
//  Quotio - Compact tunnel status indicator
//

import SwiftUI

struct TunnelStatusBadge: View {
    let status: CloudflareTunnelStatus
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    init(status: CloudflareTunnelStatus, compact: Bool = false) {
        self.status = status
        self.compact = compact
    }
    
    @State private var rotationAngle: Double = 0
    @State private var feedbackScale: CGFloat = 1
    @State private var feedbackHaloOpacity: Double = 0
    @State private var isHovered = false

    private var feedbackSettleDelayMilliseconds: Int {
        TopFeedbackRhythm.pulseMilliseconds(reduceMotion: reduceMotion)
    }

    private func restartTransitionSpinner() {
        rotationAngle = 0
        guard !reduceMotion, status == .starting || status == .stopping else { return }
        withMotionAwareAnimation(.linear(duration: QuotioMotion.Duration.looping).repeatForever(autoreverses: false), reduceMotion: reduceMotion) {
            rotationAngle = 360
        }
    }

    private func triggerStateFeedback(for newStatus: CloudflareTunnelStatus) {
        guard !reduceMotion, newStatus == .active || newStatus == .error else {
            feedbackScale = 1
            feedbackHaloOpacity = 0
            return
        }

        let peakScale: CGFloat = newStatus == .error ? 1.16 : 1.1
        let peakOpacity: Double = newStatus == .error ? 0.52 : 0.34

        feedbackScale = 0.95
        feedbackHaloOpacity = 0
        withMotionAwareAnimation(QuotioMotion.successEmphasis, reduceMotion: reduceMotion) {
            feedbackScale = peakScale
            feedbackHaloOpacity = peakOpacity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(feedbackSettleDelayMilliseconds)) {
            withMotionAwareAnimation(QuotioMotion.contentSwap, reduceMotion: reduceMotion) {
                feedbackScale = 1
                feedbackHaloOpacity = 0
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if status == .starting || status == .stopping {
                    Circle()
                        .stroke(status.color.opacity(0.3), lineWidth: 2)
                        .frame(width: 8, height: 8)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(status.color, lineWidth: 2)
                        .rotationEffect(Angle(degrees: rotationAngle))
                        .frame(width: 8, height: 8)
                        .onAppear {
                            restartTransitionSpinner()
                        }
                        .onDisappear {
                            rotationAngle = 0
                        }
                        .onChange(of: reduceMotion) { _, _ in
                            restartTransitionSpinner()
                        }
                } else {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                    
                    if status == .active {
                        Circle()
                            .stroke(status.color.opacity(0.3), lineWidth: 2)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .scaleEffect(feedbackScale)
            .overlay(
                Circle()
                    .stroke(status.color.opacity(feedbackHaloOpacity), lineWidth: 2)
                    .scaleEffect(1.35)
                    .opacity(feedbackHaloOpacity)
            )
            .motionAwareAnimation(QuotioMotion.successEmphasis, value: feedbackScale)
            .frame(width: 12, height: 12)
            
            if !compact {
                Text(status.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.color)
            }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(status.color.opacity(isHovered ? 0.16 : 0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(isHovered ? 0.3 : 0.2), lineWidth: 0.5)
        )
        .onHover { hovering in
            withMotionAwareAnimation(QuotioMotion.hover, reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .motionAwareAnimation(QuotioMotion.hover, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("tunnel.status".localized(fallback: "隧道状态"))
        .accessibilityValue(status.displayName)
        .onChange(of: status) { oldStatus, newStatus in
            if oldStatus != newStatus {
                restartTransitionSpinner()
                triggerStateFeedback(for: newStatus)
            }
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        TunnelStatusBadge(status: .idle)
        TunnelStatusBadge(status: .starting)
        TunnelStatusBadge(status: .active)
        TunnelStatusBadge(status: .stopping)
        TunnelStatusBadge(status: .error)
        
        Divider()
        
        TunnelStatusBadge(status: .active, compact: true)
    }
    .padding()
}
