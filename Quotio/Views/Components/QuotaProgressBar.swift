//
//  QuotaProgressBar.swift
//  Quotio
//

import SwiftUI

/// Progress bar for displaying quota/usage percentage
struct QuotaProgressBar: View {
    let percent: Double
    var tint: Color = .accentColor
    var height: CGFloat = 8
    
    private var clamped: Double {
        min(100, max(0, percent))
    }

    private var semanticTint: Color {
        switch clamped {
        case ..<10:
            return .semanticDanger
        case ..<30:
            return .semanticWarning
        case ..<50:
            return .semanticAccentSecondary
        default:
            return tint
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * clamped / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(semanticTint)
                    .frame(width: fillWidth)
                    .motionAwareAnimation(.smooth(duration: 0.3), value: clamped)
            }
        }
        .frame(height: height)
        .accessibilityLabel("quota.progress".localized(fallback: "配额进度"))
        .accessibilityValue("\(Int(clamped))%")
    }
}

#Preview {
    VStack(spacing: 16) {
        QuotaProgressBar(percent: 75, tint: .semanticSuccess)
        QuotaProgressBar(percent: 50, tint: .semanticWarning)
        QuotaProgressBar(percent: 25, tint: .semanticDanger)
        QuotaProgressBar(percent: 100, tint: .semanticInfo)
    }
    .padding()
    .frame(width: 300)
}
