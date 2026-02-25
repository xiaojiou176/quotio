# Quotio Debug Runbook

## 1. 快速定位顺序

1. 确认当前模式（Full / Quota-Only）
2. 确认代理进程状态（CLIProxyAPI 是否启动、端口是否可用）
3. 确认 API 请求链路与 UI 状态是否一致
4. 最后排查 provider fetcher 与本地配置写入

## 2. 最小验证命令

```bash
xcodebuild -project Quotio.xcodeproj -scheme Quotio -destination "platform=macOS" build
xcodebuild -project Quotio.xcodeproj -scheme Quotio -destination "platform=macOS" test
./scripts/test.sh
./scripts/xcode-test-stable.sh
```

稳定测试建议优先使用 `./scripts/xcode-test-stable.sh`：
- 预检失败会立刻返回 `2`
- 运行超时会强制终止并返回 `124`
- 长测每隔 `HEARTBEAT_SECONDS`（默认 `15`）输出心跳，避免无日志死等
- 失败返回 `1`，通过返回 `0`
- 日志与结果摘要自动落盘到 `.runtime-cache/test_output/quotio-xcode-test-stable/<timestamp>/`

## 3. 常见故障 -> 首查路径

- 启停代理异常：`Quotio/Services/Proxy/CLIProxyManager.swift`
- 网络桥接异常：`Quotio/Services/Proxy/ProxyBridge.swift`
- 管理 API 异常：`Quotio/Services/ManagementAPIClient.swift`
- 菜单栏显示异常：`Quotio/Services/StatusBarManager.swift`、`Quotio/Services/StatusBarMenuBuilder.swift`
- 配额显示异常：`Quotio/Services/QuotaFetchers/*`、`Quotio/ViewModels/QuotaViewModel.swift`
- 屏幕渲染异常：`Quotio/Views/Screens/*`、`Quotio/Views/Components/*`

## 4. 日志与证据

- Request/usage 相关查看 `Logs` 页面与 RequestTracker 链路
- UI 行为回归建议附截图和触发路径
- 任何修复都要附 build/test 结果

## 4.1 Review Queue 稳定性排查

- 取消任务后若 `codex` 子进程未退出，优先排查：`Quotio/Services/CLIExecutor.swift`
- 若出现 `Worker running` 长时间不结束且日志几乎不更新，优先检查 `CLIExecutor` 的 stdout/stderr 消费是否正常（防止 pipe backpressure）
- Review Queue worker 并发窗口固定上限为 `8`，排查入口：`Quotio/Services/CodexReviewQueueService.swift`
- 工作区路径输入时历史刷新采用 debounce + 后台 I/O，排查入口：
  - `Quotio/Views/Screens/ReviewQueueScreen.swift`
  - `Quotio/ViewModels/ReviewQueueViewModel.swift`
- 若历史目录缺失 `summary.json`，阶段回退判定依赖 `config.json` 与 `aggregate.md/fix.md` 文件组合
- 运行态观测优先看 Review Queue 的 `观测性` 面板（phase、耗时、事件流）
- 单个 worker 的现场证据优先看对应 `worker-xx.md`、`worker-xx.stdout.log`、`worker-xx.stderr.log`

## 5. 文档同步要求

调试路径、日志语义、验证命令变化时，必须同步更新：

- `README.md`
- `docs/codebase-structure-architecture-code-standards.md`
- `CHANGELOG.md`
