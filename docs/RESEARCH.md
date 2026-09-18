# 相关工作与有限范围查重

检索日期：2026-09-18。该记录是选题研究，不是主办方查重结论，不能证明所有公开、未公开或尚未被索引的项目都不重叠。

## 检索方法

使用 MoonBit 包索引 `moon search <关键词> --limit 15`（部分查询 limit 20），检索 rename、filesystem、patch、dependency、batch-rename、file-rename、rollback、migration、bulk、collision、transaction-plan、文件重命名。结果按相关性截断，不能视为全库遍历。进一步通过 `moon add` 下载最近似的发布包，阅读元数据和源码，而非仅凭名称判断。

| 候选与版本 | 阅读证据 | 与本项目关系 |
| --- | --- | --- |
| [cli/mv 0.1.4](https://mooncakes.io/docs/cli/mv)，[仓库](https://github.com/moonbit-community/cmd) | main.mbt 的 move_one、逐来源移动循环及 fs.rename 调用；Apache-2.0 | 是带覆盖策略、备份等选项的实际移动命令。检查的版本未提供任意来源—目标关系的循环规划、完整快照前缀定位与意图日志核对接口。 |
| [MoonTxnKit 0.4.0](https://github.com/black-duck666/MoonTxnKit) | 包 README、模块元数据、事务与 WAL 接口；Apache-2.0 | 是 MVCC/隔离级别、保存点和逻辑日志的通用事务库。不是文件名称依赖图规划库，不能仅因为双方都有 rollback/log 就视作同一能力。 |

其他语言已有成熟批量改名工具，例如 [batch_rename（Ruby）](https://github.com/claui/batch_rename) 和 [refine（Rust）](https://github.com/rsalmei/refine)。本项目不声称首创批量改名、临时名拆环或撤销算法。它的复用价值是：在 MoonBit 内提供不依赖磁盘和 UI 的类型化规划、身份守恒模拟、快照恢复以及日志与现场核对。

## 有限源码比较

将本项目七个核心 .mbt 文件（不含测试与生成物）与上述两个下载包的全部 .mbt 文件比较。处理方式为逐行去除 // 后文本、空行与空白，再比较连续八个非空行组成的窗口；这是粗略文本检查，不是语义查重，也不正确解析字符串中的 //。

| 范围 | .mbt 文件数 | 不重复的八行窗口 | 与本项目相同窗口 |
| --- | ---: | ---: | ---: |
| 本项目核心 | 7 | 1323 | — |
| cli/mv 0.1.4 | 1 | 196 | 0 |
| MoonTxnKit 0.4.0 | 13 | 1447 | 0 |

零相同窗口只表示该方法未检出连续八行的规范化文本重复，不等于零功能重叠，不代表官方重复率，也无法发现改写、短片段或未纳入的来源。没有从上述候选移植代码；开发使用 AI 辅助，标准库许可单独列明。

## 选题边界

本项目交付规划与恢复分析库，真实文件执行、持久化和并发隔离由调用者实现。避免把演示网页或 JSON 包装当作核心贡献。MoonBit 独立示例和 Wasm-GC 测试用于证明核心不依赖 JS。实现规模、性能及限制见 VALIDATION.md 和 DESIGN.md；不以行数或提交数量替代复用价值。
