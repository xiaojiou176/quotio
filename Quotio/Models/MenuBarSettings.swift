//
//  MenuBarSettings.swift
//  Quotio
//
//  Menu bar quota display settings with persistence
//

import Foundation
import SwiftUI

// MARK: - Menu Bar Quota Item

/// Represents a single item selected for menu bar display
struct MenuBarQuotaItem: Codable, Identifiable, Hashable {
    let provider: String      // AIProvider.rawValue
    let accountKey: String    // email or account identifier
    
    var id: String { "\(provider)_\(accountKey)" }
    
    /// Get the AIProvider enum value
    var aiProvider: AIProvider? {
        // Handle "copilot" alias
        if provider == "copilot" {
            return .copilot
        }
        return AIProvider(rawValue: provider)
    }
    
    /// Short display symbol for the provider
    var providerSymbol: String {
        aiProvider?.menuBarSymbol ?? "?"
    }
}

// MARK: - Color Mode

/// Color mode for menu bar quota display
enum MenuBarColorMode: String, Codable, CaseIterable, Identifiable {
    case colored = "colored"       // Green/Yellow/Red based on quota %
    case monochrome = "monochrome" // White/Gray only
    
    var id: String { rawValue }
    
    var localizationKey: String {
        switch self {
        case .colored: return "settings.menubar.colored"
        case .monochrome: return "settings.menubar.monochrome"
        }
    }
}

// MARK: - Menu Bar Quota Display Item

/// Data for displaying a single quota item in menu bar
struct MenuBarQuotaDisplayItem: Identifiable {
    let id: String
    let providerSymbol: String
    let accountShort: String
    let percentage: Double
    let provider: AIProvider
    
    var statusColor: Color {
        if percentage > 50 { return .green }
        if percentage > 20 { return .orange }
        return .red
    }
}

// MARK: - Settings Manager

/// Manager for menu bar display settings with persistence
@MainActor
@Observable
final class MenuBarSettingsManager {
    static let shared = MenuBarSettingsManager()
    
    private let defaults = UserDefaults.standard
    private let selectedItemsKey = "menuBarSelectedQuotaItems"
    private let colorModeKey = "menuBarColorMode"
    private let showQuotaKey = "menuBarShowQuota"
    
    /// Whether to show quota in menu bar
    var showQuotaInMenuBar: Bool {
        didSet { defaults.set(showQuotaInMenuBar, forKey: showQuotaKey) }
    }
    
    /// Selected items to display
    var selectedItems: [MenuBarQuotaItem] {
        didSet { saveSelectedItems() }
    }
    
    /// Color mode (colored vs monochrome)
    var colorMode: MenuBarColorMode {
        didSet { defaults.set(colorMode.rawValue, forKey: colorModeKey) }
    }
    
    /// Maximum number of items to display in menu bar
    let maxDisplayItems = 3
    
    private init() {
        self.showQuotaInMenuBar = defaults.bool(forKey: showQuotaKey)
        self.colorMode = MenuBarColorMode(rawValue: defaults.string(forKey: colorModeKey) ?? "") ?? .colored
        self.selectedItems = Self.loadSelectedItems(from: defaults, key: selectedItemsKey)
    }
    
    private func saveSelectedItems() {
        if let data = try? JSONEncoder().encode(selectedItems) {
            defaults.set(data, forKey: selectedItemsKey)
        }
    }
    
    private static func loadSelectedItems(from defaults: UserDefaults, key: String) -> [MenuBarQuotaItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([MenuBarQuotaItem].self, from: data) else {
            return []
        }
        return items
    }
    
    /// Add an item to display
    func addItem(_ item: MenuBarQuotaItem) {
        guard !selectedItems.contains(item) else { return }
        selectedItems.append(item)
    }
    
    /// Remove an item
    func removeItem(_ item: MenuBarQuotaItem) {
        selectedItems.removeAll { $0.id == item.id }
    }
    
    /// Check if item is selected
    func isSelected(_ item: MenuBarQuotaItem) -> Bool {
        selectedItems.contains(item)
    }
    
    /// Toggle item selection
    func toggleItem(_ item: MenuBarQuotaItem) {
        if isSelected(item) {
            removeItem(item)
        } else {
            addItem(item)
        }
    }
    
    /// Remove items that no longer exist in quota data
    func pruneInvalidItems(validItems: [MenuBarQuotaItem]) {
        let validIds = Set(validItems.map(\.id))
        selectedItems.removeAll { !validIds.contains($0.id) }
    }
}
