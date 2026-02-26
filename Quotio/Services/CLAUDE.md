# CLAUDE.md

Claude 在 `quotio/Quotio/Services` 的执行说明。

## 0. 项目目的 / 技术栈 / 目录导航 / 最小验证

- 项目目的：维护 Quotio 服务层的业务能力与运行稳定性（代理、配额、配置、状态栏协作）。
- 技术栈：Swift 6 + Swift Concurrency（`actor`、`@MainActor`）+ macOS 15+。
- 目录导航（首查）：
  - 代理与运行：`CLIProxyManager.swift`、`ProxyBridge.swift`
  - API 与配额：`ManagementAPIClient.swift`、`*QuotaFetcher.swift`
  - Agent 配置：`AgentConfigurationService.swift`、`AgentDetectionService.swift`
- 最小验证命令：
  - `./scripts/test.sh`
  - `xcodebuild -project Quotio.xcodeproj -scheme Quotio -configuration Debug build`

## 1. 这里负责什么

该目录承载业务服务层：
- Proxy 生命周期与桥接
- API 客户端
- Quota 抓取器
- Agent 配置服务
- 状态栏与通知服务

## 2. 并发模型优先级

- UI 绑定状态：`@MainActor @Observable`
- 线程安全异步服务：`actor`

新增服务请先对齐现有并发模式，不要混用导致竞态。

## 3. 首选阅读

- `AGENTS.md`（本目录）
- `../ViewModels/` 相关调用方
- `CLIProxyManager.swift` / `ManagementAPIClient.swift` 等关键服务

## 4. 最小验证

- 编译通过（Xcode build）
- 改动涉及的服务链路可触发并观察到预期状态
- 若改网络层，关注连接复用/关闭行为是否回归

## 5. 体系三 + 四补充

### 5.1 Lazy Load

先读本目录 `AGENTS.md`，再按任务只加载目标服务与直接调用方。

### 5.2 写前必搜

```bash
rg -n "关键词|服务名|actor名|manager名" .
rg --files . | rg "关键词|Service|Fetcher|Manager|Actor"
```

若不复用已有实现，交付报告必须写明理由。建议附加：
```text
[Reuse Decision]
- 搜索关键词:
- 复用目标路径(如有):
- 不复用原因(如有):
```

### 5.3 密钥与门禁

- 真实密钥只允许来自根 `.env` 或进程环境变量。
- 禁止把 token/password 写入源码、日志、提交信息。
- 交付前执行：

```bash
bash ../../../scripts/secret-governance-check.sh
bash ../../../.githooks/pre-commit
```
