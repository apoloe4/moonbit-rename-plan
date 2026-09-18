# API 与集成合同

## 类型化入口

| API | 输入与结果 |
| --- | --- |
| `filename_problem` / `name_key` | 单层名称检查、显式大小写策略 |
| `validate_request` | 收集快照、来源、目标与占用冲突 |
| `build_plan` | 返回 Plan；`problems` 非空时 steps 为空 |
| `dependency_components` | 对已通过预检的映射分解 chain/cycle/case-only |
| `generate_mappings` / `default_rule` | 名称规则展开，结果仍需 build_plan |
| `replace_literal` | Unicode 标量上的非重叠字面替换 |
| `replay` | 验证每步来源拼写、身份和目标空闲，再返回新快照 |
| `simulate` | 某个成功步骤数后的快照、剩余步骤与逆序回退 |
| `reverse_steps` | 生成反向操作；可执行性仍由 replay 检查 |
| `snapshot_diff` | 按精确名称比较 missing/unexpected/identity_changed |
| `recover` | 查找所有匹配前缀；多解或无解时不返回继续步骤 |
| `recover_from_checkpoint` | 在外部可信完成步数下验证完整快照 |
| `verify_boundaries` | 检查每个前缀的最终状态和回退状态，最多 200 步 |
| `audit_plan` | 对消费者自行构造的 Plan 检查顺序索引、回放及最终状态 |
| `inspect_journal` / `step_receipt` | 校验 intent/result 序列与计划绑定 |
| `reconcile_journal` | 将可信日志与现场快照交叉验证 |
| `render_markdown` / `render_dot` | 生成可审阅的非执行型报告 |
| `plan_json` / `recover_json` / `journal_json` | FFI 异常转为 error JSON；不向 JS 抛 MoonBit 异常 |

`rules_json` 是同一请求协议的规则预览别名。完整类型签名由 `moon info` 生成，见根目录 pkg.generated.mbti。

## 核心不变量

1. 每个操作前来源存在，精确拼写及 identity 与计划相符。
2. 目标在选定名称策略下必须不存在，禁止覆盖。
3. 每一步保持条目数与 identity 多重集合不变。
4. 正向回放后精确名称与 identity 等于 desired。
5. 任意成功前缀的逆序操作恢复 initial。
6. 临时名避开所有原始名称、全部最终目标及之前生成的临时名。

类型化公开结构可由调用方构造。对外部构造的 Plan 应先 `audit_plan`；对不可信 JSON 只接受原始请求重新规划，不信任导入的 steps。

## 日志协议

每个尝试包含 `intent`，之后接 `completed` 或 `failed`。结果必须对应同一个 step、source、target、identity；成功后才推进步数。失败后可重新 intent 重试。每个成功改名步骤应由接入方原子执行；日志的持久化顺序由接入方保障。

- `consistent`：观察到已确认前缀，可从下一步继续。
- `retry-pending`：最后 intent 对应操作尚未生效；如重新执行，应沿用该未完成意图，不重复追加 intent。
- `acknowledge-pending`：操作已生效，缺少 completed；先持久化 `nextReceipt`，再进行返回的 continueSteps。
- `complete`：日志确认全部步骤，且现场一致。
- `diverged` / `invalid-journal`：停止，不给出自动继续或回退步骤。

失败结果意味着该原子改名未生效；若外部执行器把部分成功误记为 failed，现场核对会拒绝。日志没有签名、认证或持久化功能，须由调用方提供可信存储。同内容 identity 的场景下，可信日志可以补充纯快照无法提供的进度证据。

## 三个集成场景

- 批量素材重命名工具：先用名称规则生成映射，调用规划器检查占用和循环，再由自己的 UI 展示计划并决定是否执行。
- 跨平台文件管理器：针对显式名称等价策略预检大小写改名，消费者实现自己的平台适配和执行前复查。
- 批处理作业恢复工具：保存原始请求与 intent/result 日志，重启后提供完整目录身份快照，核对执行窗口并拒绝外部篡改。

## 必须由接入方处理

文件权限、同卷原子重命名能力、符号链接/硬链接、Unicode 文件系统等价、目录嵌套、跨设备移动、锁、fsync、事务日志可靠性和内容身份冲突。本库未实现真实文件执行器。回退也是一组需要逐步验证的计划，不能保证任意外部文件变化后仍可执行。
