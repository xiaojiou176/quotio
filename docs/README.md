# Quotio Docs Index

本目录存放 Quotio（macOS 15+）的项目级文档与治理文档。

## 核心文档

- `project-overview-prd.md`: 产品目标、用户画像、功能边界
- `codebase-summary.md`: 代码结构、模块职责、关键数据流
- `codebase-structure-architecture-code-standards.md`: 架构与代码规范
- `debug-runbook.md`: 故障排查与恢复流程
- `documentation-policy.md`: 文档治理与门禁约束

## 维护规则

- 变更 `quotio/Quotio/**` 时，必须同步本目录或 `quotio/README*.md`
- 变更 UI 视图时，需同步 `docs/ui-ux/ui-ux-documentation.md` 或本目录文档
- 合入前建议在根仓执行：`bash scripts/doc-ci-gate.sh --all`
