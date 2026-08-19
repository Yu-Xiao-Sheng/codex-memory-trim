# 子技能：compress —— 压缩记忆表达

把冗长的记忆条目改写为简短、清晰的表达。**只做表达压缩，不做事实裁剪之外的删除**（成批删除线程走 `trim.md`）。

## 适用与不适用

- 压缩对象：`MEMORY.md`（主要目标）和 `memory_summary.md`（超过 ~45 行时轻度压缩）。
- 不压缩：`rollout_summaries/` 与 `raw_memories.md`（由 DB 重新渲染，改了会被还原，白费功夫）；`extensions/ad_hoc/notes/`（用户原话，权威措辞不改动）。
- 事实安全网：细节原文仍在 rollout_summaries 里，MEMORY.md 压缩可容忍措辞级损失，但下列内容**一个都不能丢**：文件路径、ID/哈希/流水线号、命令与 API 端点、数量边界（如 `1..10`）、决策边界（fail-closed、验收门槛）、`[ad-hoc note]` 标记、关键词列表（检索入口，可精简到 8-10 个但不可清空）。

## 流程

1. 共享前置：跑 `collect.py`、备份、确认 git 基线干净（见 SKILL.md）。
2. 逐组压缩 `MEMORY.md`，按下面的风格规则改写；同组内近似重复的条目合并为一条。
3. `memory_summary.md` 仅在超行数时压缩；全局偏好条目可缩句但语义必须完整，效率优先/Superpowers 门控/两次失败止损等规则关键词保留。
4. 校验：`collect.py` 引用报告应为 OK；记录压缩前后字节数（`stat -c %s`）。
5. git 提交（共享模板），汇报：每组压缩幅度、合并了哪些重复条目。

## 风格规则（带对照）

- 症状-原因-修复三段式 → 只留教训：`Symptom: jq 报错。Cause: pod inspect 返回对象。Fix: 先查 JSON 类型` → `podman pod inspect 可能返回对象而非数组，先查 JSON 类型再写 jq 过滤`。
- "when the user says \"<长原话>\" -> ..." → 规则已通用化的只留规则；确有约束力的引语保留 ≤10 词片段。
- 被动长句 → 祈使短句；一条 bullet 一个事实；删掉“必须重新验证”类重复限定词（全局偏好已覆盖）。
- 标注“历史数字/需重算”的具体数值 → 删除并留一句“具体数值见摘要文件”；指针行保持 `文件名 (thread_id=...; ≤10词状态)` 格式。
- 长枚举 → 收敛为模式（`target/debug/{deps,incremental,build,examples,.fingerprint}` 是好形式；逐项罗列五台主机是坏形式，除非主机本身是关键路由信息）。
