# Services Layer

30 services implementing business logic, API clients, and system integrations.

## 0) Purpose / Stack / Navigation / Verification

- Purpose: own service/runtime logic for Quotio, including proxy lifecycle, API access, quota fetching, and agent configuration.
- Stack: Swift 6, Swift Concurrency (`actor`, `@MainActor @Observable`), macOS 15+.
- Directory navigation:
  - Core runtime: `CLIProxyManager.swift`, `ProxyBridge.swift`, `ProxyStorageManager.swift`
  - API client: `ManagementAPIClient.swift`
  - Quota pipeline: `*QuotaFetcher.swift`
  - Agent config: `AgentConfigurationService.swift`, `AgentDetectionService.swift`
- Minimal verification commands:
  - `./scripts/test.sh`
  - `xcodebuild -project Quotio.xcodeproj -scheme Quotio -configuration Debug build`

## Architecture

Three concurrency patterns used:

| Pattern | Count | Use Case |
|---------|-------|----------|
| `@MainActor @Observable` | 11 | UI-bound state (StatusBarManager, CLIProxyManager) |
| `actor` | 13 | Thread-safe async (API clients, quota fetchers) |
| Singleton (`static let shared`) | 12 | App-wide coordination |

## Where to Look

| Task | File | Pattern |
|------|------|---------|
| Add quota fetcher | Create `*QuotaFetcher.swift` | Actor, see `ClaudeCodeQuotaFetcher` |
| Add API endpoint | `ManagementAPIClient.swift` | Actor methods with `async throws` |
| Menu bar changes | `StatusBarManager.swift` + `StatusBarMenuBuilder.swift` | Singleton + builder |
| Proxy lifecycle | `CLIProxyManager.swift` | `start()`, `stop()`, `toggle()` |
| Auth commands | `CLIProxyManager.swift` | `runAuthCommand()` extension |
| Binary management | `ProxyStorageManager.swift` | Versioned storage with symlinks |

## Service Categories

### Core Infrastructure
- `CLIProxyManager` - Proxy process lifecycle, binary download, auth commands
- `ProxyBridge` - TCP bridge layer, forces `Connection: close`
- `ProxyStorageManager` - Versioned binary storage, SHA256 verification
- `CompatibilityChecker` - Version compatibility validation

### API Clients
- `ManagementAPIClient` - Primary HTTP client for CLIProxyAPI (actor)

### Quota Fetchers (all actors)
| Fetcher | Provider | Method |
|---------|----------|--------|
| `AntigravityQuotaFetcher` | Antigravity | Protobuf DB injection |
| `ClaudeCodeQuotaFetcher` | Claude Code | Filesystem auth scan |
| `CopilotQuotaFetcher` | GitHub Copilot | OAuth API |
| `CursorQuotaFetcher` | Cursor IDE | SQLite direct read |
| `TraeQuotaFetcher` | Trae IDE | SQLite direct read |
| `OpenAIQuotaFetcher` | OpenAI/Codex | OAuth API |
| `GeminiCLIQuotaFetcher` | Gemini CLI | Filesystem scan |
| `CodexCLIQuotaFetcher` | Codex CLI | Filesystem scan |

### Agent Configuration
- `AgentDetectionService` - Detects installed CLI agents
- `AgentConfigurationService` - Generates and applies agent configs
- `ShellProfileManager` - Modifies shell profiles (.zshrc, .bashrc)

### UI Services
- `StatusBarManager` - Menu bar icon and state (singleton)
- `StatusBarMenuBuilder` - NSMenu construction
- `NotificationManager` - macOS notifications
- `LanguageManager` - Localization with String Catalogs

### Antigravity Suite
- `AntigravityAccountSwitcher` - Account switching orchestration
- `AntigravityDatabaseService` - SQLite operations
- `AntigravityProcessManager` - IDE process management
- `AntigravityProtobufHandler` - Protobuf encoding/decoding

## Conventions

### Creating a New Service

**Singleton (UI-bound):**
```swift
@MainActor @Observable
final class MyService {
    static let shared = MyService()
    private init() {}
    
    var state: String = ""
    
    func doSomething() async { ... }
}
```

**Actor (thread-safe):**
```swift
actor MyFetcher {
    func fetch() async throws -> Data {
        // Safe concurrent access
    }
}
```

### API Client Pattern
```swift
actor MyAPIClient {
    private let session: URLSession
    
    func fetchData() async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw APIError.httpError(statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
```

### Quota Fetcher Template
```swift
actor NewProviderQuotaFetcher {
    func fetchQuota() async throws -> ProviderQuota {
        // 1. Locate auth file/database
        // 2. Extract credentials
        // 3. Call API or parse local data
        // 4. Return normalized ProviderQuota
    }
}
```

## Critical Rules

- **CLIProxyManager**: Base URL always points to CLIProxyAPI directly
- **ProxyStorageManager**: Never delete current version symlink
- **ProxyBridge**: Target host always localhost
- **ManagementAPIClient**: Uses `Connection: close` to prevent stale connections

## Dependencies Between Services

```
QuotaViewModel
├── CLIProxyManager (weak ref)
├── ManagementAPIClient
├── All QuotaFetchers
├── DirectAuthFileService
├── NotificationManager
└── RequestTracker

CLIProxyManager
├── ProxyBridge
├── ProxyStorageManager
└── CompatibilityChecker

StatusBarManager
└── StatusBarMenuBuilder
```

## Governance Addendum (System 3+4)

### Lazy Load

1. Read this file then sibling `CLAUDE.md`.
2. Load only related service files and their direct caller in `../ViewModels/`.

### Search Before Writing

```bash
rg -n "keyword|serviceName|actorName" .
rg --files . | rg "keyword|Service|Fetcher|Manager"
```

If not reusing an existing implementation, include this in the delivery report:
```text
[Reuse Decision]
- Search keywords:
- Reused path (if any):
- Reason for not reusing (if any):
```

### Secret Boundary and Gate

- Real keys/tokens must come from root `.env` or process ENV only.
- Never hardcode credentials or print tokens in logs.
- Before commit, run:

```bash
bash ../../../scripts/secret-governance-check.sh
bash ../../../.githooks/pre-commit
```
