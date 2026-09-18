# 验证记录

日期：2026-09-18。Windows 本地环境：MoonBit moon 0.1.20260915 / moonc 0.10.13，Node.js 24.17.0。GitHub Actions 使用 Ubuntu 与 Node.js 22，线上结果以仓库 Actions 实际记录为准。

## 已完成验证

- `moon fmt --check`、两个目标的 `moon check --deny-warn`。
- `moon test --target js --deny-warn`：47 组通过。
- `moon test --target wasm-gc --deny-warn`：47 组通过（同一套测试，不合并声称为 94 个不同测试）。
- `moon run cmd/demo --target wasm-gc`：直接调用 MoonBit 类型化接口，交换、模拟及恢复输出正确。
- `moon info`：生成公开接口文件。
- `npm run build`、`npm test`：10 组 Node 测试通过。
- 浏览器交互：交换计划第 1 步现场唯一匹配；修改身份后拒绝继续；相同身份交换报告多个前缀；占用目标报告 blocked。

测试包括四文件全部 24 种排列、固定种子 80 个随机排列、每个成功边界的继续与逆序回退、名称碰撞、临时名占用、大小写别名、未知 JSON 字段、日志失败重试及 intent/result 中断窗口。Node 测试以独立状态机复核规划步骤，并使用临时目录验证 SHA-256 快照不修改文件。

## 性能与规模

[benchmark.json](benchmark.json) 是一次本地运行结果，包含 JSON 解析与报告生成，验证 10、100、500、1000 条目循环及中点恢复。单次计时没有统计置信度，不代表其他机器或实际磁盘吞吐。

七个核心 MoonBit 文件约 1535 行，MoonBit 测试约 690 行，另有独立 MoonBit 使用示例。数字包含空行和注释；不计生成 JS、标准库或外部依赖，不声称达到任何赛事规模门槛。核心规划、校验、规则、日志与恢复均由 MoonBit 实现。

## 明确未验证的能力

没有实际磁盘改名执行器；没有断电持久化保证、跨进程锁、递归目录、跨文件系统移动、完整 Unicode 文件名等价或 Native/LLVM 后端支持。快照身份由调用者保证，重复内容可以产生恢复歧义；日志默认来自可信调用者，不带签名。上述边界不能用通过逻辑测试来替代。
