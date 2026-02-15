# CLAUDE.md

Claude 在 `quotio/scripts` 的执行说明。

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
