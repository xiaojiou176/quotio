# Quotio/Services/Proxy/CLIProxyManager.swift

[← Back to Module](../modules/root/MODULE.md) | [← Back to INDEX](../INDEX.md)

## Overview

- **Lines:** 1956
- **Language:** Swift
- **Symbols:** 64
- **Public symbols:** 0

## Symbol Table

| Line | Kind | Name | Visibility | Signature |
| ---- | ---- | ---- | ---------- | --------- |
| 9 | class | CLIProxyManager | (internal) | `class CLIProxyManager` |
| 176 | method | init | (internal) | `init()` |
| 217 | fn | restartProxyIfRunning | (private) | `private func restartProxyIfRunning()` |
| 235 | fn | updateConfigValue | (private) | `private func updateConfigValue(pattern: String,...` |
| 255 | fn | updateConfigPort | (private) | `private func updateConfigPort(_ newPort: UInt16)` |
| 259 | fn | updateConfigHost | (private) | `private func updateConfigHost(_ host: String)` |
| 263 | fn | ensureApiKeyExistsInConfig | (private) | `private func ensureApiKeyExistsInConfig()` |
| 312 | fn | updateConfigLogging | (internal) | `func updateConfigLogging(enabled: Bool)` |
| 320 | fn | updateConfigRoutingStrategy | (internal) | `func updateConfigRoutingStrategy(_ strategy: St...` |
| 325 | fn | updateConfigProxyURL | (internal) | `func updateConfigProxyURL(_ url: String?)` |
| 353 | fn | applyBaseURLWorkaround | (internal) | `func applyBaseURLWorkaround()` |
| 382 | fn | removeBaseURLWorkaround | (internal) | `func removeBaseURLWorkaround()` |
| 427 | fn | restartProxyIfRunning | (private) | `private func restartProxyIfRunning()` |
| 445 | fn | ensureConfigExists | (private) | `private func ensureConfigExists()` |
| 479 | fn | syncSecretKeyInConfig | (private) | `private func syncSecretKeyInConfig()` |
| 495 | fn | regenerateManagementKey | (internal) | `func regenerateManagementKey() async throws` |
| 530 | fn | syncProxyURLInConfig | (private) | `private func syncProxyURLInConfig()` |
| 543 | fn | syncCustomProvidersToConfig | (private) | `private func syncCustomProvidersToConfig()` |
| 560 | fn | downloadAndInstallBinary | (internal) | `func downloadAndInstallBinary() async throws` |
| 621 | fn | fetchLatestRelease | (private) | `private func fetchLatestRelease() async throws ...` |
| 642 | fn | findCompatibleAsset | (private) | `private func findCompatibleAsset(in release: Re...` |
| 667 | fn | downloadAsset | (private) | `private func downloadAsset(url: String) async t...` |
| 686 | fn | extractAndInstall | (private) | `private func extractAndInstall(data: Data, asse...` |
| 748 | fn | findBinaryInDirectory | (private) | `private func findBinaryInDirectory(_ directory:...` |
| 781 | fn | start | (internal) | `func start() async throws` |
| 913 | fn | stop | (internal) | `func stop()` |
| 969 | fn | startHealthMonitor | (private) | `private func startHealthMonitor()` |
| 983 | fn | stopHealthMonitor | (private) | `private func stopHealthMonitor()` |
| 988 | fn | performHealthCheck | (private) | `private func performHealthCheck() async` |
| 1051 | fn | cleanupOrphanProcesses | (private) | `private func cleanupOrphanProcesses() async` |
| 1105 | fn | terminateAuthProcess | (internal) | `func terminateAuthProcess()` |
| 1111 | fn | toggle | (internal) | `func toggle() async throws` |
| 1119 | fn | copyEndpointToClipboard | (internal) | `func copyEndpointToClipboard()` |
| 1124 | fn | revealInFinder | (internal) | `func revealInFinder()` |
| 1131 | enum | ProxyError | (internal) | `enum ProxyError` |
| 1162 | enum | AuthCommand | (internal) | `enum AuthCommand` |
| 1200 | struct | AuthCommandResult | (internal) | `struct AuthCommandResult` |
| 1206 | mod | extension CLIProxyManager | (internal) | - |
| 1207 | fn | runAuthCommand | (internal) | `func runAuthCommand(_ command: AuthCommand) asy...` |
| 1239 | fn | appendOutput | (internal) | `func appendOutput(_ str: String)` |
| 1243 | fn | tryResume | (internal) | `func tryResume() -> Bool` |
| 1254 | fn | safeResume | (internal) | `@Sendable func safeResume(_ result: AuthCommand...` |
| 1354 | mod | extension CLIProxyManager | (internal) | - |
| 1384 | fn | checkForUpgrade | (internal) | `func checkForUpgrade() async` |
| 1432 | fn | saveInstalledVersion | (private) | `private func saveInstalledVersion(_ version: St...` |
| 1440 | fn | fetchAvailableReleases | (internal) | `func fetchAvailableReleases(limit: Int = 10) as...` |
| 1462 | fn | versionInfo | (internal) | `func versionInfo(from release: GitHubRelease) -...` |
| 1468 | fn | fetchGitHubRelease | (private) | `private func fetchGitHubRelease(tag: String) as...` |
| 1490 | fn | findCompatibleAsset | (private) | `private func findCompatibleAsset(from release: ...` |
| 1523 | fn | performManagedUpgrade | (internal) | `func performManagedUpgrade(to version: ProxyVer...` |
| 1577 | fn | downloadAndInstallVersion | (private) | `private func downloadAndInstallVersion(_ versio...` |
| 1624 | fn | startDryRun | (private) | `private func startDryRun(version: String) async...` |
| 1695 | fn | promote | (private) | `private func promote(version: String) async throws` |
| 1730 | fn | rollback | (internal) | `func rollback() async throws` |
| 1763 | fn | stopTestProxy | (private) | `private func stopTestProxy() async` |
| 1792 | fn | stopTestProxySync | (private) | `private func stopTestProxySync()` |
| 1818 | fn | findUnusedPort | (private) | `private func findUnusedPort() throws -> UInt16` |
| 1828 | fn | isPortInUse | (private) | `private func isPortInUse(_ port: UInt16) -> Bool` |
| 1847 | fn | createTestConfig | (private) | `private func createTestConfig(port: UInt16) -> ...` |
| 1875 | fn | cleanupTestConfig | (private) | `private func cleanupTestConfig(_ configPath: St...` |
| 1883 | fn | isNewerVersion | (private) | `private func isNewerVersion(_ newer: String, th...` |
| 1886 | fn | parseVersion | (internal) | `func parseVersion(_ version: String) -> [Int]` |
| 1918 | fn | findPreviousVersion | (private) | `private func findPreviousVersion() -> String?` |
| 1931 | fn | migrateToVersionedStorage | (internal) | `func migrateToVersionedStorage() async throws` |

## Memory Markers

### 🟢 `NOTE` (line 207)

> Bridge mode default is registered in AppDelegate.applicationDidFinishLaunching()

### 🟢 `NOTE` (line 319)

> Changes take effect after proxy restart (CLIProxyAPI does not support live routing API)

### 🟢 `NOTE` (line 1415)

> Notification is handled by AtomFeedUpdateService polling

