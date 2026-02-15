# CLAUDE.md

Claude 在 `quotio/Quotio/Views` 的执行说明。

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
