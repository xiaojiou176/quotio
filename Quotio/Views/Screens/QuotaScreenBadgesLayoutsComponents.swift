//
//  QuotaScreenBadgesLayoutsComponents.swift
//  Quotio
//

import SwiftUI

struct PlanBadgeV2Compact: View {
    let planName: String
    
    private var tierConfig: (name: String, color: Color) {
        let lowercased = planName.lowercased()
        
        // Check for Pro variants
        if lowercased.contains("pro") {
            return ("Pro", Color.semanticAccentSecondary)
        }
        
        // Check for Plus
        if lowercased.contains("plus") {
            return ("Plus", Color.semanticInfo)
        }
        
        // Check for Team
        if lowercased.contains("team") {
            return ("Team", Color.semanticWarning)
        }
        
        // Check for Enterprise
        if lowercased.contains("enterprise") {
            return ("Enterprise", Color.semanticDanger)
        }
        
        // Free/Standard
        if lowercased.contains("free") || lowercased.contains("standard") {
            return ("Free", .secondary)
        }
        
        // Default: use display name
        let displayName = planName
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return (displayName, .secondary)
    }
    
    var body: some View {
        Text(tierConfig.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(tierConfig.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tierConfig.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Plan Badge V2

struct PlanBadgeV2: View {
    let planName: String
    
    private var planConfig: (color: Color, icon: String) {
        let lowercased = planName.lowercased()
        
        // Handle compound names like "Pro Student"
        if lowercased.contains("pro") && lowercased.contains("student") {
            return (Color.semanticAccentSecondary, "graduationcap.fill")
        }
        
        switch lowercased {
        case "pro":
            return (Color.semanticAccentSecondary, "crown.fill")
        case "plus":
            return (Color.semanticInfo, "plus.circle.fill")
        case "team":
            return (Color.semanticWarning, "person.3.fill")
        case "enterprise":
            return (Color.semanticDanger, "building.2.fill")
        case "free":
            return (.secondary, "person.fill")
        case "student":
            return (Color.semanticSuccess, "graduationcap.fill")
        default:
            return (.secondary, "person.fill")
        }
    }
    
    private var displayName: String {
        planName
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: planConfig.icon)
                .font(.caption)
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(planConfig.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(planConfig.color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Subscription Badge V2

struct SubscriptionBadgeV2: View {
    let info: SubscriptionInfo
    
    private var tierConfig: (name: String, color: Color) {
        let tierId = info.tierId.lowercased()
        let tierName = info.tierDisplayName.lowercased()
        
        // Check for Ultra tier (highest priority)
        if tierId.contains("ultra") || tierName.contains("ultra") {
            return ("Ultra", Color.semanticWarning)
        }
        
        // Check for Pro tier
        if tierId.contains("pro") || tierName.contains("pro") {
            return ("Pro", Color.semanticAccentSecondary)
        }
        
        // Check for Free/Standard tier
        if tierId.contains("standard") || tierId.contains("free") || 
           tierName.contains("standard") || tierName.contains("free") {
            return ("Free", .secondary)
        }
        
        // Fallback: use the display name from API
        return (info.tierDisplayName, .secondary)
    }
    
    var body: some View {
        Text(tierConfig.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(tierConfig.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tierConfig.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Antigravity Display Group

struct QuotaAntigravityDisplayGroup: Identifiable {
    let name: String
    let percentage: Double
    let models: [ModelQuota]
    
    var id: String { name }
}

// MARK: - Antigravity Group Row

struct AntigravityGroupRow: View {
    let group: QuotaAntigravityDisplayGroup
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }

    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var remainingPercent: Double {
        max(0, min(100, group.percentage))
    }
    
    private var groupIcon: String {
        if group.name.contains("Claude") { return "brain.head.profile" }
        if group.name.contains("Image") { return "photo" }
        if group.name.contains("Flash") { return "bolt.fill" }
        return "sparkles"
    }
    
    var body: some View {
        let displayPercent = displayHelper.displayPercent(remainingPercent: remainingPercent)
        let statusColor = displayHelper.statusTint(remainingPercent: remainingPercent)
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: groupIcon)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                
                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if group.models.count > 1 {
                    Text(String(group.models.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                Text(String(format: "%.0f%%", displayPercent))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
                
                if let firstModel = group.models.first,
                   firstModel.formattedResetTime != "—" && !firstModel.formattedResetTime.isEmpty {
                    Text(firstModel.formattedResetTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(statusColor.gradient)
                        .frame(width: proxy.size.width * (displayPercent / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Antigravity Lowest Bar Layout

struct AntigravityLowestBarLayout: View {
    let groups: [QuotaAntigravityDisplayGroup]
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var sorted: [QuotaAntigravityDisplayGroup] {
        groups.sorted { $0.percentage < $1.percentage }
    }
    
    private var lowest: QuotaAntigravityDisplayGroup? {
        sorted.first
    }
    
    private var others: [QuotaAntigravityDisplayGroup] {
        Array(sorted.dropFirst())
    }
    
    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if let lowest = lowest {
                // Hero row for bottleneck
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(lowest.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "%.0f%%", displayPercent(for: lowest.percentage)))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(displayHelper.statusTint(remainingPercent: lowest.percentage))
                            .monospacedDigit()
                    }
                    
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(displayHelper.statusTint(remainingPercent: lowest.percentage).gradient)
                                .frame(width: proxy.size.width * (displayPercent(for: lowest.percentage) / 100))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(12)
                .background(displayHelper.statusTint(remainingPercent: lowest.percentage).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Others as compact text rows
            if !others.isEmpty {
                VStack(spacing: 4) {
                    ForEach(others) { group in
                        HStack {
                            Text(group.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", displayPercent(for: group.percentage)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(displayHelper.statusTint(remainingPercent: group.percentage))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Antigravity Ring Layout

struct AntigravityRingLayout: View {
    let groups: [QuotaAntigravityDisplayGroup]
    
    private var settings: MenuBarSettingsManager { MenuBarSettingsManager.shared }
    private var displayHelper: QuotaDisplayHelper {
        QuotaDisplayHelper(displayMode: settings.quotaDisplayMode)
    }
    
    private var columns: [GridItem] {
        let count = min(max(groups.count, 1), 4)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
    
    private func displayPercent(for remainingPercent: Double) -> Double {
        displayHelper.displayPercent(remainingPercent: remainingPercent)
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(groups) { group in
                VStack(spacing: 6) {
                    RingProgressView(
                        percent: displayPercent(for: group.percentage),
                        size: 44,
                        lineWidth: 5,
                        tint: displayHelper.statusTint(remainingPercent: group.percentage),
                        showLabel: true
                    )
                    
                    Text(group.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Standard Lowest Bar Layout

