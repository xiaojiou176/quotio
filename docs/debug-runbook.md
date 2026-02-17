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
```

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

## 5. 文档同步要求

调试路径、日志语义、验证命令变化时，必须同步更新：

- `README.md`
- `docs/codebase-structure-architecture-code-standards.md`
- `CHANGELOG.md`
