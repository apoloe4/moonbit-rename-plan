# MoonRename Plan

**可复用的 MoonBit 批量改名规划与恢复分析库。** 输入完整名称快照和改名关系，输出无覆盖的逻辑步骤、循环解释、中断点状态及恢复证据。核心不依赖 JavaScript、DOM、文件系统或网络。

交换 `a.txt` 和 `b.txt` 不能直接顺序覆盖。这里会生成：`a → 临时名`、`b → a`、`临时名 → b`，并验证每一个执行边界的继续与回退路径。

## 能力与边界

- 完整预检：非法单层名称、重复来源、重复目标、大小写别名、缺失来源、被未移动条目占用的目标。
- 依赖分析：链、交换、多个独立循环、仅改变大小写；确定性临时名称避开全部现存名和目标名。
- 规划与验证：保留文件身份的逐步重命名、前缀模拟、逆序回退、全部中断边界检查、公开 Plan 的一致性审计。
- 恢复分析：完整现场快照匹配；身份改变、缺失或多余文件时拒绝给出继续步骤；重复身份造成多解时明确报告歧义。
- 日志核对：intent/completed/failed 状态机，失败重试、顺序检查、日志与现场交叉验证，识别操作完成但结果未记录的窗口。
- 规则展开：前后缀、字面替换、扩展名、稳定编号、后缀筛选、ASCII 大小写；转换后仍走同一套冲突检查。
- JSON、Markdown、Graphviz DOT 报告，命令行、SHA-256 目录快照和中文交互工作台。

**这是规划库，不是文件执行器。** 命令行与网页不重命名、不删除、不写入用户文件。接入方负责真实操作、日志持久化、执行前重新验证和并发隔离；不能把逻辑回退验证当成磁盘崩溃原子性保证。

支持 JavaScript 与 Wasm-GC 后端；已验证 MoonBit `moonc v0.10.13` / `moon 0.1.20260915`。不声称支持未测试的 Native/LLVM 后端。

## 快速运行

浏览器与 CLI 需要 Node.js 22+，无需 npm 依赖。仓库包含编译产物，初次体验不需要 MoonBit：

```sh
npm start
# http://127.0.0.1:4174
node cli.mjs plan examples/swap.json
node cli.mjs simulate examples/swap.json 1
node cli.mjs recover examples/swap.json examples/interrupted.json
node cli.mjs reconcile examples/swap.json examples/pending-journal.json examples/interrupted.json
```

网页示例覆盖交换、循环、占用冲突、大小写改名、相同内容歧义和规则编号。拖动中断点，可查看当前快照与回退步骤；点击“用此快照检查恢复”，再修改 identity，观察恢复分析如何拒绝不一致的现场。

CLI JSON 输出到 stdout，错误信息到 stderr。退出码：0 表示可用/匹配，1 表示 blocked/diverged/ambiguous/invalid-journal，2 表示输入或 IO 错误。0 不表示执行过改名。

## 直接在 MoonBit 中复用

安装工具链后，无需 Node.js 运行独立调用示例：

```sh
moon run cmd/demo --target wasm-gc
moon test --target wasm-gc
```

`cmd/demo/moon.pkg` 导入 `apoloe4/rename_plan`。该示例直接调用类型化 API：

```moonbit
let entries : Array[@planner.Entry] = [
  { name: "a.txt", identity: "file-A" },
  { name: "b.txt", identity: "file-B" },
]
let mappings : Array[@planner.Rename] = [
  { source: "a.txt", target: "b.txt" },
  { source: "b.txt", target: "a.txt" },
]
let plan = @planner.build_plan(entries, mappings, @planner.Exact)
// 调用方先检查 plan.problems，再使用 simulate / recover 等可能抛错的 API。
```

公开接口见 [API.md](docs/API.md) 和工具链生成的 [pkg.generated.mbti](pkg.generated.mbti)。当前通过 GitHub 提供源码，**尚未发布 Mooncakes**；不要把 `moon add apoloe4/rename_plan` 当成当前已可用的安装命令。

## 输入模型

```json
{
  "policy": "exact",
  "entries": [
    {"name":"a.txt","identity":"A"},
    {"name":"b.txt","identity":"B"}
  ],
  "mappings": [
    {"source":"a.txt","target":"b.txt"},
    {"source":"b.txt","target":"a.txt"}
  ],
  "completed": 1,
  "verify": true
}
```

- `entries` 必须是完整命名空间，不能只列出要改名的文件。`identity` 是调用方提供的稳定身份；允许重复，但可能导致恢复歧义。
- `policy` 为 `exact` 或 `ascii-fold`；后者只折叠 A–Z，**不模拟 NTFS/APFS 的完整 Unicode 等价规则**。不做 NFC/NFD、区域语言排序或路径归一化。
- 来源必须使用快照中的精确拼写。只接受单层文件名；采用保守的标点、控制字符、常见设备名、尾点/空格检查，不承诺穷举所有平台规则。
- `mappings` 和 `rule` 二选一。规则的序号按来源名 UTF-16 字典序分配；只对匹配 `onlySuffix` 的名称编号。扩展名不带点，空字符串表示去掉扩展名。
- 每个请求最多 1000 个条目/映射、名称最多 180 个 Unicode 标量、身份最多 512 UTF-16 单元。JSON 输入 CLI 限 2 MiB，核心限 200 万 UTF-16 单元。
- `completed` 表示成功完成的步骤数，取值 0..stepCount；`verify:true` 检查所有边界，限制 200 步。更大计划使用单个边界模拟。

## 从真实目录生成快照

```sh
node cli.mjs snapshot ./my-flat-folder > observed.json
```

只读扫描单层普通文件，单文件最多 64 MiB、目录最多 1000 条目；遇到子目录或符号链接会拒绝。内容 SHA-256 用作身份；同内容文件身份相同，因此仅凭快照可能无法区分交换前后。扫描检查文件在读取前后的基本身份/大小/时间变化，但它不是文件系统事务快照。请在目录不被修改时扫描。

## 项目结构与核心归属

| 文件 | 职责 |
| --- | --- |
| model.mbt | 数据模型、名称策略与冲突预检 |
| planner.mbt | 链/循环规划、图分解、受保护的模拟执行 |
| recovery.mbt | 快照差异、前缀定位、回退、边界验证 |
| journal.mbt | 意图/结果日志状态机与中断窗口核对 |
| rules.mbt | 确定性名称规则与编号 |
| json_api.mbt / render.mbt | 严格 JSON 边界、Markdown/DOT 输出 |
| cmd/demo/ | 独立 MoonBit 调用者，无 JS 依赖 |
| cli.mjs | 读取输入、目录快照、调用编译后的核心 |
| web/ | 薄界面、Worker 与编译产物 |

规划、校验、规则、模拟、回退和恢复算法都在 MoonBit 中；JS 不重新实现这些判断。详见 [设计说明](docs/DESIGN.md)。

## 验证

```sh
moon fmt --check
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon run cmd/demo --target wasm-gc
moon info
npm run build
npm test
npm run bench
```

47 组 MoonBit 测试分别在两个后端运行；10 组 Node.js 测试验证 CLI、只读扫描与独立状态机。包括四文件全部 24 种排列、80 个固定种子随机排列、每步恢复/回退及日志中断窗口。性能脚本检查 10/100/500/1000 条目，不把单机结果视为承诺。详见 [验证记录](docs/VALIDATION.md)。

## 相关工作与查重

[cli/mv](https://mooncakes.io/docs/cli/mv) 是实际移动命令，[MoonTxnKit](https://github.com/black-duck666/MoonTxnKit) 是通用 MVCC/逻辑事务库。本项目聚焦**完整改名关系的依赖规划、身份守恒验证及改名日志与目录快照核对**。其他语言已有批量改名产品，循环暂存也不是新发明；本项目价值在于把这组能力作为独立 MoonBit API 提供。查重范围、来源、局限与源码比较见 [RESEARCH.md](docs/RESEARCH.md)。不宣称生态唯一或保证比赛通过。

## License 与开发说明

MIT。开发使用 AI 辅助，算法、边界和测试可在本仓库核对。未移植候选项目代码；MoonBit 标准库和生成的 JS 运行时涉及 Apache-2.0，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
