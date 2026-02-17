//
//  RingProgressView.swift
//  Quotio
//
//  Circular progress indicator for quota display
//

import SwiftUI

/// Circular progress indicator for quota display
struct RingProgressView: View {
    let percent: Double
    var size: CGFloat = 32
    var lineWidth: CGFloat = 4
    var tint: Color = .accentColor
    var showLabel: Bool = false
    
    private var clamped: Double {
        min(100, max(0, percent))
    }
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: clamped / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .motionAwareAnimation(.smooth(duration: 0.3), value: clamped)
            
            // Optional center label
            if showLabel {
                Text("\(Int(clamped))%")
                    .font(.system(size: size * 0.24, weight: .bold))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("usage.ring".localized())
        .accessibilityValue(String(format: "%lld percent".localized(), Int64(clamped)))
        .accessibilityHint("usage.ring.hint".localized(fallback: "环形图显示当前使用百分比"))
    }
}

#Preview {
    HStack(spacing: 24) {
        RingProgressView(percent: 75, tint: .semanticSuccess, showLabel: true)
        RingProgressView(percent: 30, tint: .semanticWarning, showLabel: true)
        RingProgressView(percent: 5, tint: .semanticDanger, showLabel: true)
    }
    .padding()
}
