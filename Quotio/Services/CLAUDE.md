# CLAUDE.md

Claude 在 `quotio/Quotio/Services` 的执行说明。

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
