# Quotio/Views/Screens/SettingsScreen.swift

[← Back to Module](../modules/Quotio-Views-Screens/MODULE.md) | [← Back to INDEX](../INDEX.md)

## Overview

- **Lines:** 3036
- **Language:** Swift
- **Symbols:** 60
- **Public symbols:** 0

## Symbol Table

| Line | Kind | Name | Visibility | Signature |
| ---- | ---- | ---- | ---------- | --------- |
| 9 | struct | SettingsScreen | (internal) | `struct SettingsScreen` |
| 111 | struct | OperatingModeSection | (internal) | `struct OperatingModeSection` |
| 176 | fn | handleModeSelection | (private) | `private func handleModeSelection(_ mode: Operat...` |
| 195 | fn | switchToMode | (private) | `private func switchToMode(_ mode: OperatingMode)` |
| 210 | struct | RemoteServerSection | (internal) | `struct RemoteServerSection` |
| 330 | fn | saveRemoteConfig | (private) | `private func saveRemoteConfig(_ config: RemoteC...` |
| 338 | fn | reconnect | (private) | `private func reconnect()` |
| 353 | struct | UnifiedProxySettingsSection | (internal) | `struct UnifiedProxySettingsSection` |
| 573 | fn | loadConfig | (private) | `private func loadConfig() async` |
| 614 | fn | saveProxyURL | (private) | `private func saveProxyURL() async` |
| 627 | fn | saveRoutingStrategy | (private) | `private func saveRoutingStrategy(_ strategy: St...` |
| 636 | fn | saveSwitchProject | (private) | `private func saveSwitchProject(_ enabled: Bool)...` |
| 645 | fn | saveSwitchPreviewModel | (private) | `private func saveSwitchPreviewModel(_ enabled: ...` |
| 654 | fn | saveRequestRetry | (private) | `private func saveRequestRetry(_ count: Int) async` |
| 663 | fn | saveMaxRetryInterval | (private) | `private func saveMaxRetryInterval(_ seconds: In...` |
| 672 | fn | saveLoggingToFile | (private) | `private func saveLoggingToFile(_ enabled: Bool)...` |
| 681 | fn | saveRequestLog | (private) | `private func saveRequestLog(_ enabled: Bool) async` |
| 690 | fn | saveDebugMode | (private) | `private func saveDebugMode(_ enabled: Bool) async` |
| 703 | struct | LocalProxyServerSection | (internal) | `struct LocalProxyServerSection` |
| 773 | struct | NetworkAccessSection | (internal) | `struct NetworkAccessSection` |
| 807 | struct | LocalPathsSection | (internal) | `struct LocalPathsSection` |
| 831 | struct | PathLabel | (internal) | `struct PathLabel` |
| 855 | struct | NotificationSettingsSection | (internal) | `struct NotificationSettingsSection` |
| 925 | struct | QuotaDisplaySettingsSection | (internal) | `struct QuotaDisplaySettingsSection` |
| 967 | struct | RefreshCadenceSettingsSection | (internal) | `struct RefreshCadenceSettingsSection` |
| 1006 | struct | UpdateSettingsSection | (internal) | `struct UpdateSettingsSection` |
| 1048 | struct | ProxyUpdateSettingsSection | (internal) | `struct ProxyUpdateSettingsSection` |
| 1208 | fn | checkForUpdate | (private) | `private func checkForUpdate()` |
| 1222 | fn | performUpgrade | (private) | `private func performUpgrade(to version: ProxyVe...` |
| 1241 | struct | ProxyVersionManagerSheet | (internal) | `struct ProxyVersionManagerSheet` |
| 1400 | fn | sectionHeader | (private) | `@ViewBuilder   private func sectionHeader(_ tit...` |
| 1415 | fn | isVersionInstalled | (private) | `private func isVersionInstalled(_ version: Stri...` |
| 1419 | fn | refreshInstalledVersions | (private) | `private func refreshInstalledVersions()` |
| 1423 | fn | loadReleases | (private) | `private func loadReleases() async` |
| 1437 | fn | installVersion | (private) | `private func installVersion(_ release: GitHubRe...` |
| 1455 | fn | performInstall | (private) | `private func performInstall(_ release: GitHubRe...` |
| 1476 | fn | activateVersion | (private) | `private func activateVersion(_ version: String)` |
| 1494 | fn | deleteVersion | (private) | `private func deleteVersion(_ version: String)` |
| 1507 | struct | InstalledVersionRow | (private) | `struct InstalledVersionRow` |
| 1565 | struct | AvailableVersionRow | (private) | `struct AvailableVersionRow` |
| 1651 | fn | formatDate | (private) | `private func formatDate(_ isoString: String) ->...` |
| 1669 | struct | MenuBarSettingsSection | (internal) | `struct MenuBarSettingsSection` |
| 1810 | struct | AppearanceSettingsSection | (internal) | `struct AppearanceSettingsSection` |
| 1839 | struct | PrivacySettingsSection | (internal) | `struct PrivacySettingsSection` |
| 1861 | struct | GeneralSettingsTab | (internal) | `struct GeneralSettingsTab` |
| 1900 | struct | AboutTab | (internal) | `struct AboutTab` |
| 1927 | struct | AboutScreen | (internal) | `struct AboutScreen` |
| 2142 | struct | AboutUpdateSection | (internal) | `struct AboutUpdateSection` |
| 2198 | struct | AboutProxyUpdateSection | (internal) | `struct AboutProxyUpdateSection` |
| 2351 | fn | checkForUpdate | (private) | `private func checkForUpdate()` |
| 2365 | fn | performUpgrade | (private) | `private func performUpgrade(to version: ProxyVe...` |
| 2384 | struct | VersionBadge | (internal) | `struct VersionBadge` |
| 2436 | struct | AboutUpdateCard | (internal) | `struct AboutUpdateCard` |
| 2527 | struct | AboutProxyUpdateCard | (internal) | `struct AboutProxyUpdateCard` |
| 2701 | fn | checkForUpdate | (private) | `private func checkForUpdate()` |
| 2715 | fn | performUpgrade | (private) | `private func performUpgrade(to version: ProxyVe...` |
| 2734 | struct | LinkCard | (internal) | `struct LinkCard` |
| 2821 | struct | ManagementKeyRow | (internal) | `struct ManagementKeyRow` |
| 2915 | struct | LaunchAtLoginToggle | (internal) | `struct LaunchAtLoginToggle` |
| 2973 | struct | UsageDisplaySettingsSection | (internal) | `struct UsageDisplaySettingsSection` |

