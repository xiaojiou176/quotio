//
//  SmallProgressView.swift
//  Quotio
//
//  A workaround for SwiftUI ProgressView constraint issues on macOS.
//  Using .controlSize(.small) with ProgressView causes AppKit layout
//  constraint conflicts due to floating-point precision issues with
//  intrinsic size (~16.5 points).
//
//  This component uses NSProgressIndicator directly via NSViewRepresentable
//  to avoid the SwiftUI/AppKit constraint bridging issues.
//

import SwiftUI
import AppKit

/// A small indeterminate progress indicator that avoids AppKit constraint issues.
///
/// Use this instead of `ProgressView().controlSize(.small)` to prevent
/// the "maximum length that doesn't satisfy min <= max" constraint error.
struct SmallProgressView: View {
    let size: CGFloat
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseLoading = false
    @State private var haloOpacity = 0.14
    
    init(
        size: CGFloat = 16,
        accessibilityLabel: String = "common.loading".localized(fallback: "加载中"),
        accessibilityValue: String = "common.loading.inProgress".localized(fallback: "进行中"),
        accessibilityHint: String = "common.loading.waitHint".localized(fallback: "请稍候")
    ) {
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityHint = accessibilityHint
    }
    
    var body: some View {
        Group {
            if reduceMotion {
                ReducedMotionProgressGlyph()
            } else {
                ZStack {
                    Circle()
                        .strokeBorder(.secondary.opacity(haloOpacity), lineWidth: 1)
                        .scaleEffect(pulseLoading ? 1 : 0.88)
                    SmallProgressIndicator()
                        .scaleEffect(pulseLoading ? 1 : 0.94)
                        .opacity(pulseLoading ? 1 : 0.72)
                }
                .onAppear {
                    withMotionAwareAnimation(
                        QuotioMotion.contentSwap.repeatForever(autoreverses: true),
                        reduceMotion: reduceMotion
                    ) {
                        pulseLoading = true
                        haloOpacity = 0.26
                    }
                }
                .onDisappear {
                    pulseLoading = false
                    haloOpacity = 0.14
                }
            }
        }
            .motionAwareAnimation(QuotioMotion.contentSwap, value: reduceMotion)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Internal NSViewRepresentable that creates a properly sized NSProgressIndicator
private struct SmallProgressIndicator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimation(nil)
        
        container.addSubview(indicator)
        
        // Center the indicator in the container
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let indicator = nsView.subviews.first as? NSProgressIndicator {
            if !indicator.isHidden {
                indicator.startAnimation(nil)
            }
        }
    }
}

private struct ReducedMotionProgressGlyph: View {
    var body: some View {
        Circle()
            .strokeBorder(.tertiary, lineWidth: 2)
            .overlay(
                Circle()
                    .trim(from: 0.12, to: 0.58)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-55))
            )
    }
}

#Preview {
    HStack(spacing: 24) {
        VStack {
            SmallProgressView()
            Text("Default (16)")
                .font(.caption)
        }
        
        VStack {
            SmallProgressView(size: 8)
            Text("Size 8")
                .font(.caption)
        }
        
        VStack {
            SmallProgressView(size: 12)
            Text("Size 12")
                .font(.caption)
        }
        
        VStack {
            SmallProgressView(size: 20)
            Text("Size 20")
                .font(.caption)
        }
    }
    .padding()
}
