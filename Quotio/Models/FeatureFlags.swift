//
//  FeatureFlags.swift
//  Quotio
//
//  Client-side rollout flags for UI upgrades.
//

import Foundation
import Observation

@MainActor
@Observable
final class FeatureFlagManager {
    static let shared = FeatureFlagManager()

    private let defaults = UserDefaults.standard
    private let enhancedUILayoutKey = "feature.enhancedUILayout"
    private let enhancedObservabilityKey = "feature.enhancedObservability"
    private let accessibilityHardeningKey = "feature.accessibilityHardening"

    var enhancedUILayout: Bool {
        didSet { defaults.set(enhancedUILayout, forKey: enhancedUILayoutKey) }
    }

    var enhancedObservability: Bool {
        didSet { defaults.set(enhancedObservability, forKey: enhancedObservabilityKey) }
    }

    var accessibilityHardening: Bool {
        didSet { defaults.set(accessibilityHardening, forKey: accessibilityHardeningKey) }
    }

    private init() {
        if defaults.object(forKey: enhancedUILayoutKey) == nil {
            defaults.set(true, forKey: enhancedUILayoutKey)
        }
        if defaults.object(forKey: enhancedObservabilityKey) == nil {
            defaults.set(true, forKey: enhancedObservabilityKey)
        }
        if defaults.object(forKey: accessibilityHardeningKey) == nil {
            defaults.set(true, forKey: accessibilityHardeningKey)
        }

        self.enhancedUILayout = defaults.bool(forKey: enhancedUILayoutKey)
        self.enhancedObservability = defaults.bool(forKey: enhancedObservabilityKey)
        self.accessibilityHardening = defaults.bool(forKey: accessibilityHardeningKey)
    }
}
