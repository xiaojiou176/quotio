# Quotio

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="screenshots/menu_bar_dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="screenshots/menu_bar.png" />
    <img alt="Quotio Banner" src="screenshots/menu_bar.png" height="600" />
  </picture>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat" alt="Platform macOS" />
  <img src="https://img.shields.io/badge/language-Swift-orange.svg?style=flat" alt="Language Swift" />
  <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat" alt="License MIT" />
  <a href="https://discord.gg/dFzeZ7qS"><img src="https://img.shields.io/badge/Discord-Join%20us-5865F2.svg?style=flat&logo=discord&logoColor=white" alt="Discord" /></a>
  <a href="README.vi.md"><img src="https://img.shields.io/badge/lang-Tiếng%20Việt-red.svg?style=flat" alt="Vietnamese" /></a>
  <a href="README.zh.md"><img src="https://img.shields.io/badge/lang-zh--CN-green.svg?style=flat" alt="Chinese" /></a>
  <a href="README.fr.md"><img src="https://img.shields.io/badge/lang-Français-blue.svg?style=flat" alt="French" /></a>
</p>

<p align="center">
  <strong>The ultimate command center for your AI coding assistants on macOS.</strong>
</p>

Quotio is a native macOS application for managing **CLIProxyAPI** - a local proxy server that powers your AI coding agents. It helps you manage multiple AI accounts, track quotas, and configure CLI tools in one place.

## ✨ Features

- **🔌 Multi-Provider Support**: Connect accounts from Gemini, Claude, OpenAI Codex, Qwen, Vertex AI, iFlow, Antigravity, Kiro, Trae, and GitHub Copilot via OAuth or API keys.
- **📊 Standalone Quota Mode**: View quota and accounts without running the proxy server - perfect for quick checks.
- **🚀 One-Click Agent Configuration**: Auto-detect and configure AI coding tools like Claude Code, OpenCode, Gemini CLI, and more.
- **🧵 Automated Review Queue**: Launch parallel Codex review runs with built-in prompt presets, rerun failed workers only, review workspace run history, optionally aggregate/deduplicate findings, then trigger one-click fix execution.
- **📈 Real-time Dashboard**: Monitor request traffic, token usage, and success rates live.
- **📉 Smart Quota Management**: Visual quota tracking per account with automatic failover strategies (Round Robin / Fill First).
- **🔑 API Key Management**: Generate and manage API keys for your local proxy.
- **🖥️ Menu Bar Integration**: Quick access to server status, quota overview, and custom provider icons from your menu bar.
- **🔔 Notifications**: Alerts for low quotas, account cooling periods, or service issues.
- **🔄 Auto-Update**: Built-in Sparkle updater for seamless updates.
- **🌍 Multilingual**: English, Vietnamese, and Simplified Chinese support.

## 🤖 Supported Ecosystem

### AI Providers
| Provider | Auth Method |
|----------|-------------|
| Google Gemini | OAuth |
| Anthropic Claude | OAuth |
| OpenAI Codex | OAuth |
| Qwen Code | OAuth |
| Vertex AI | Service Account JSON |
| iFlow | OAuth |
| Antigravity | OAuth |
| Kiro | OAuth |
| GitHub Copilot | OAuth |

### IDE Quota Tracking (Monitor Only)
| IDE | Description |
|-----|-------------|
| Cursor | Auto-detected when installed and logged in |
| Trae | Auto-detected when installed and logged in |

> **Note**: These IDEs are only used for quota usage monitoring. They cannot be used as providers for the proxy.

### Compatible CLI Agents
Quotio can automatically configure these tools to use your centralized proxy:
- Claude Code
- Codex CLI
- Gemini CLI
- Amp CLI
- OpenCode
- Factory Droid

## 🚀 Installation

### Requirements
- macOS 15.0 (Sequoia) or later
- Internet connection for OAuth authentication

### Homebrew (Recommended)
```bash
brew tap nguyenphutrong/tap
brew install --cask quotio
```

### Download
Download the latest `.dmg` from the [Releases](https://github.com/nguyenphutrong/quotio/releases) page.

> ⚠️ **Note**: The app is not signed with an Apple Developer certificate yet. If macOS blocks the app, run:
> ```bash
> xattr -cr /Applications/Quotio.app
> ```

### Building from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nguyenphutrong/quotio.git
   cd Quotio
   ```

2. **Open in Xcode:**
   ```bash
   open Quotio.xcodeproj
   ```

3. **Build and Run:**
   - Select the "Quotio" scheme
   - Press `Cmd + R` to build and run

> The app will automatically download the `CLIProxyAPI` binary on first launch.

## ✅ Testing

Run local automated checks before opening a PR:

```bash
xcodebuild -project Quotio.xcodeproj -scheme Quotio -destination "platform=macOS" build
xcodebuild -project Quotio.xcodeproj -scheme Quotio -destination "platform=macOS" test
./scripts/xcode-test-stable.sh
```

Stable runner notes:
- Adds preflight checks (tooling/project/scheme visibility)
- Enforces timeout (`TIMEOUT_SECONDS`, default `1200`)
- Persists logs and result summary to `.runtime-cache/test_output/quotio-xcode-test-stable/<timestamp>/`
- Returns explicit exit code: `0=pass`, `1=fail`, `124=timeout`, `2=preflight-fail`

CI gates:
- PR: `.github/workflows/pr-ci.yml` (build + test)
- Nightly: `.github/workflows/nightly-ci.yml` (build + test)

Documentation governance:
- Policy: `docs/documentation-policy.md`
- Local gate: `./scripts/doc-ci-gate.sh`
- CI gate: `.github/workflows/doc-governance.yml`
- Debug runbook: `docs/debug-runbook.md`

### Codex JSONL Parser Stability (2026-02-18)

- Review Queue now exposes a dedicated parser helper:
  - `CodexReviewQueueService.parseLastAgentMessageFromJSONL(_:)`
- Parser behavior is validated for forward compatibility:
  - interleaved unknown/new event types do not break last `item.completed(agent_message)` extraction
  - no-agent-message payloads correctly return `nil`
- Regression coverage:
  - `QuotioTests.testParseLastAgentMessageIgnoresInterleavedUnknownEvents`
  - `QuotioTests.testParseLastAgentMessageReturnsNilWhenNoAgentMessage`

### Review Queue Runtime Stability (2026-02-18)

- `CLIExecutor.executeCLIWithInput(...)` now handles task cancellation explicitly:
  - avoids cancellation-induced busy loops in wait polling
  - terminates (and force-kills if needed) the child process promptly on cancel
- `CLIExecutor.executeCLIWithInput(...)` now streams stdout/stderr while the process is running:
  - prevents large JSONL output from filling pipe buffers and stalling worker completion
  - preserves partial output for timeout/cancel diagnostics
- Review worker scheduling now uses a bounded concurrency window (`max 8`) instead of launching all prompts at once.
- Workspace-history refresh no longer performs heavy directory scanning on every keystroke in the workspace input; typing path changes are debounced and resolved off the main thread.
- History fallback phase inference (without `summary.json`) now treats aggregate-only runs (`runAggregate=true`, `runFix=false`) as completed when `aggregate.md` exists.
- Review Queue UI now exposes clearer runtime telemetry:
  - live progress summary (`done/running/failed`)
  - elapsed timer updates every second during active runs
  - per-worker quick links to `worker/stdout/stderr` outputs
  - dedicated observability panel with timestamped run-event timeline

## 📖 Usage

### 1. Start the Server
Launch Quotio and click **Start** on the dashboard to initialize the local proxy server.

### 2. Connect Accounts
Go to **Providers** tab → Click on a provider → Authenticate via OAuth or import credentials.

### 3. Configure Agents
Go to **Agents** tab → Select an installed agent → Click **Configure** → Choose Automatic or Manual mode.

### 4. Monitor Usage
- **Dashboard**: Overall health and traffic
- **Quota**: Per-account usage breakdown
- **Logs**: Raw request/response logs for debugging

## ⚙️ Settings

- **Port**: Change the proxy listening port
- **Routing Strategy**: Round Robin or Fill First
- **Auto-start**: Launch proxy automatically when Quotio opens
- **Notifications**: Toggle alerts for various events

## 📚 Request Logging & Auditability

Quotio records auditable request evidence for traffic that passes through its local proxy bridge.

- What is recorded per request:
  - request identity: `requestId`, timestamp, HTTP method/path
  - route evidence: provider/model + resolved provider/model after fallback
  - source evidence: client source classification and source header/User-Agent signal
  - execution result: `statusCode`, latency, request/response byte size
  - optional payload evidence: raw payload snippet (truncated when oversized)
- Success/failure rule:
  - A request is treated as success only when `statusCode` is `2xx`.
  - Non-2xx or missing status code is tracked as failure and included in error-focused audit output.
- Local persistence and export:
  - Local history file: `~/Library/Application Support/Quotio/request-history.json`
  - Logs screen can export an audit package containing recent requests, recent failures, aggregate stats, and settings/auth evidence snapshot.
- Payload evidence control:
  - `ui.captureRequestPayloadEvidence` (enabled by default) controls whether payload snippets are captured.
  - Captured payload text is stored raw and truncated for oversized requests.
- Settings audit trail:
  - `~/Library/Application Support/Quotio/settings-audit.json` records setting old/new values in raw form (no masking) for full-fidelity debugging.

For backend-side file logging in CLIProxyAPI, configure management endpoints:
- `GET/PUT/PATCH /v0/management/request-log`
- `GET/PUT/PATCH /v0/management/logging-to-file`
- Request log files include `Prompt Debug` summaries (system/messages/input/contents/prompt), so each upstream AI prompt can be traced during debugging.

## 📸 Screenshots

### Dashboard
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/dashboard_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/dashboard.png" />
  <img alt="Dashboard" src="screenshots/dashboard.png" />
</picture>

### Providers
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/provider_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/provider.png" />
  <img alt="Providers" src="screenshots/provider.png" />
</picture>

### Agent Setup
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/agent_setup_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/agent_setup.png" />
  <img alt="Agent Setup" src="screenshots/agent_setup.png" />
</picture>

### Quota Monitoring
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/quota_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/quota.png" />
  <img alt="Quota Monitoring" src="screenshots/quota.png" />
</picture>

### Fallback Configuration
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/fallback_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/fallback.png" />
  <img alt="Fallback Configuration" src="screenshots/fallback.png" />
</picture>

### API Keys
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/api_keys_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/api_keys.png" />
  <img alt="API Keys" src="screenshots/api_keys.png" />
</picture>

### Logs
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/logs_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/logs.png" />
  <img alt="Logs" src="screenshots/logs.png" />
</picture>

### Settings
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/settings_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/settings.png" />
  <img alt="Settings" src="screenshots/settings.png" />
</picture>

### Menu Bar
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/menu_bar_dark.png" />
  <source media="(prefers-color-scheme: light)" srcset="screenshots/menu_bar.png" />
  <img alt="Menu Bar" src="screenshots/menu_bar.png" height="600" />
</picture>

## 🤝 Contributing

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/amazing-feature`)
3. Commit your Changes (`git commit -m 'Add amazing feature'`)
4. Push to the Branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 💬 Community

Join our Discord community to get help, share feedback, and connect with other users:

<a href="https://discord.gg/dFzeZ7qS">
  <img src="https://img.shields.io/badge/Discord-Join%20our%20community-5865F2.svg?style=for-the-badge&logo=discord&logoColor=white" alt="Join Discord" />
</a>

## ⭐ Star History

<picture>
  <source
    media="(prefers-color-scheme: dark)"
    srcset="
      https://api.star-history.com/svg?repos=nguyenphutrong/quotio&type=Date&theme=dark
    "
  />
  <source
    media="(prefers-color-scheme: light)"
    srcset="
      https://api.star-history.com/svg?repos=nguyenphutrong/quotio&type=Date
    "
  />
  <img
    alt="Star History Chart"
    src="https://api.star-history.com/svg?repos=nguyenphutrong/quotio&type=Date"
  />
</picture>

## 📊 Repo Activity

![Repo Activity](https://repobeats.axiom.co/api/embed/884e7349c8939bfd4bdba4bc582b6fdc0ecc21ee.svg "Repobeats analytics image")

## 💖 Contributors

We couldn't have done this without you. Thank you! 🙏

<a href="https://github.com/nguyenphutrong/quotio/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=nguyenphutrong/quotio" />
</a>

## 📄 License

MIT License. See `LICENSE` for details.
