# CLAUDE.md

Claude 在 `quotio/Quotio/Views` 的执行说明。

## 0. 项目目的 / 技术栈 / 目录导航 / 最小验证

- 项目目的：维护 Quotio 的 UI 交互与展示一致性，确保组件复用与页面行为稳定。
- 技术栈：SwiftUI + Swift 6（View + Environment 注入模式）。
- 目录导航（首查）：
  - 组件：`Components/`
  - 页面：`Screens/`
  - 引导：`Onboarding/`
  - 状态来源：`../ViewModels/`
- 最小验证命令：
  - `xcodebuild -project Quotio.xcodeproj -scheme Quotio -configuration Debug build`
  - `./scripts/test.sh`

## 1. 这里负责什么

该目录是 UI 展示层：
- Components（可复用组件）
- Screens（页面）
- Onboarding（引导）

## 2. 修改原则

- 优先复用已有组件，不重复造轮子
- 状态来源尽量通过 ViewModel 注入（Environment）
- 避免把业务逻辑塞进 View

## 3. 首选阅读

- `AGENTS.md`（本目录）
- `../ViewModels/`（状态来源）
- `../Models/`（类型与导航枚举）

## 4. 最小验证

- 编译通过
- Light/Dark 下主要 UI 不破版
- 改动页面关键交互可正常触发

## 5. 体系三 + 四补充

### 5.1 Lazy Load

先读本目录 `AGENTS.md`，再只加载受影响的 UI 文件与对应 ViewModel。

### 5.2 写前必搜

```bash
rg -n "关键词|组件名|页面名" .
rg --files . | rg "关键词|Screen|Card|View|Row|Component"
```

若不复用已有实现，交付报告必须写明理由。建议附加：
```text
[Reuse Decision]
- 搜索关键词:
- 复用目标路径(如有):
- 不复用原因(如有):
```

### 5.3 密钥与门禁

- 禁止在 UI 文案、日志、提交信息中出现真实密钥。
- 真实密钥仅允许来自根 `.env` 或进程环境变量。
- 交付前执行：

```bash
bash ../../../scripts/secret-governance-check.sh
bash ../../../.githooks/pre-commit
```
