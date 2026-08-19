# 子技能：trim —— 检测重复、清理过期记忆

按 usage 数据与引用关系做三层一致的选择性清理。

## 第 0 步：安全检查 + 备份

```bash
python3 ~/.codex/skills/codex-memory-trim/scripts/collect.py
```

共享前置见 SKILL.md（备份、整理竞争检查）。`collect.py` 显示 `memory_consolidate_global` 为 running 时等它结束；正在运行的 Codex 进程无需停止。

## 第 1 步：确定删除候选

依据 `collect.py` 的 orphan / usage 输出，删除候选须**同时满足**：

- `MEMORY.md` 已不引用（孤儿）；
- `usage_count` < 20（高引用记忆即使孤儿也保留）；
- 会话完成超两周且属一次性工作（READY 回显、一次性查询/配置、被新版本取代的旧版本记录、连命令都没记录的空记忆）。

永远保留：`extensions/ad_hoc/notes/` 全部、`selected_for_phase2=0` 的新线程、进行中项目组、项目仍需要的记忆型 skill（能力已入项目且项目内有实现的可删）。

## 第 2 步：三层一致删除

对每个候选线程**同时**删除三处（缺一会被同步还原或留下悬空引用）：

1. `rollout_summaries/<file>.md`；
2. `raw_memories.md` 中 `## Thread \`<thread_id>\`` 段落；
3. DB 行：`DELETE FROM stage1_outputs WHERE thread_id IN (...)`。

**thread_id 必须从文件/DB 内容程序化提取，禁止手抄**（存在隐形字符差异导致漏删的先例）。DB 无 sqlite3 CLI 时用 `python3 -c "import sqlite3; ..."`，操作后 `PRAGMA wal_checkpoint(TRUNCATE)`。

## 第 3 步：重写 MEMORY.md 与 memory_summary.md

保持格式（`# Task Group` + `scope/applies_to/reuse_rule` + tasks + keywords + 指针）：

- 合并同域小组，组数控制在 ~15-20；
- 全局性规则（worktree 禁令、真实证据、pre→手动验收→prod、"请只回复"、密钥不落盘、效率优先、Superpowers 门控、两次失败止损）只留 `memory_summary.md`，组内仅保留领域特定规则；
- 指针压缩为 `文件名 (thread_id=...; ≤10词状态)`；删除"需重算"历史数字、失效路由、被后续会话推翻的旧状态（写前核对基线 diff 中更新的事实）；
- `memory_summary.md` 控制在 ~40 行，保留全部全局偏好和 `[ad-hoc note]` 标记。

## 第 4 步：校验 + 提交

`collect.py` 应无 missing/orphan 报告；摘要文件数 == raw 线程数 == DB 已选行数。然后按共享模板 git 提交，`git status --short` 为空才算完成。

## 回滚

文件层：`git -C ~/.codex/memories reset --hard <上一提交>`；全量：`~/.codex/backups/memories-before-trim-*.tar.gz` + 同时间戳 sqlite。
