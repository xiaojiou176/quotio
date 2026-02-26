# CLAUDE.md

Claude 在 `quotio/scripts` 的执行说明。

## 0. 项目目的 / 技术栈 / 目录导航 / 最小验证

- 项目目的：保障 Quotio 的构建、打包、公证与发布脚本稳定可复现。
- 技术栈：Bash + Xcode CLI + Apple notarization + Sparkle appcast。
- 目录导航（首查）：
  - 发布总控：`release.sh`
  - 构建打包：`build.sh`、`package.sh`
  - 公证与签名：`notarize.sh`、`generate-appcast.sh`
  - 公共函数：`config.sh`
- 最小验证命令：
  - `bash -n scripts/*.sh`
  - `./scripts/build.sh`

## 1. 这里负责什么

该目录用于构建与发布脚本：
- build/package/notarize/release
- 版本号与 changelog 更新
- appcast 生成

## 2. 修改原则

- 优先保持脚本幂等与可回滚
- 不随意改变发布产物命名与输出路径
- 涉及签名/公证变量时，保留缺失变量时的安全降级行为

## 3. 首选阅读

- `AGENTS.md`（本目录）
- `release.sh`, `build.sh`, `package.sh`, `notarize.sh`
- `../RELEASE.md`

## 4. 最小验证

- 脚本语法与基础参数路径正确
- 至少跑通与本次修改相关的脚本步骤
- 输出产物路径与既有约定一致

## 5. 体系三 + 四补充

### 5.1 Lazy Load

先读 `AGENTS.md`，再只加载与本次任务相关的脚本文件。

### 5.2 写前必搜

```bash
rg -n "关键词|脚本名|环境变量名" .
rg --files . | rg "关键词|\\.sh$|config|release|build"
```

若不复用已有实现，交付报告必须写明理由。建议附加：
```text
[Reuse Decision]
- 搜索关键词:
- 复用目标路径(如有):
- 不复用原因(如有):
```

### 5.3 密钥与门禁

- 真实密钥仅允许来自根 `.env` 或进程环境变量。
- 禁止在脚本输出、日志、提交信息中泄漏密钥。
- 交付前执行：

```bash
bash ../../scripts/secret-governance-check.sh
bash ../../.githooks/pre-commit
```
