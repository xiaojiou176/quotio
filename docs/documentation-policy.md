# Quotio Documentation Policy

## 目标

确保 SwiftUI 客户端行为、UI 交互、测试与发布流程的文档同步更新，避免 AI 改动造成上下文偏移。

## DoD（文档维度）

以下改动必须同步更新文档：

- `Quotio/**` 业务逻辑或 UI 行为变化
- `scripts/**` 测试/发布流程变化
- `.github/workflows/**` CI/CD 与安全门禁变化

## Doc-Change Contract

| 代码改动 | 必须同步 |
|---|---|
| `Quotio/**` | `README.md` 或 `docs/**` 或 `AGENTS.md` 或 `CHANGELOG.md` |
| `scripts/**` | `RELEASE.md` 或 `docs/**` |
| `.github/workflows/**` | 本文件 |

## 门禁

- 脚本：`./scripts/doc-ci-gate.sh`
- workflow：`.github/workflows/doc-governance.yml`

## Active Branch Note (2026-02-17)

当前分支包含 `.github/workflows/*`、`Quotio/**`、`scripts/**` 的持续改动，提交前必须保持本文件同步更新。
