---
name: codex-memory-trim
description: Manage Codex's native global memory (~/.codex/memories) with three sub-procedures - trim (audit + dedupe + three-layer cleanup), compress (rewrite verbose memories into concise form), and add-global (add a custom global rule/preference). Use when the user asks to 精简/清理/整理/压缩 Codex 记忆, 去重, 简化冗长记忆, 添加/写入/修改全局记忆 or a global rule.
---

# Codex 全局记忆管理（trim / compress / add-global）

按用户需求只读取对应子技能文件执行，不要全量加载：

| 用户意图 | 读取 |
|---|---|
| 清理/去重/删除过期记忆 | `subskills/trim.md` |
| 压缩冗长表达、简化措辞 | `subskills/compress.md` |
| 添加自定义全局记忆/规则 | `subskills/add-global.md` |

## 共享事实（所有子技能依赖，不要重新推导）

- 分层：`sessions/*.jsonl`（不可变原始证据）→ `raw_memories.md` / `rollout_summaries/`（整理输入，由 `~/.codex/memories_1.sqlite` 表 `stage1_outputs` 重新渲染，手改会被还原）→ `MEMORY.md`（检索层）/ `memory_summary.md`（会话启动时注入的快照，文件头 `v1`）。
- `usage_count`（stage1_outputs 列）= 检索命中次数，是保留/删除的核心依据。
- `~/.codex/memories/.git` 是整理基线：Phase 2 以 HEAD→工作区 diff 决定巩固内容。**任何手工修改必须以 git 提交收尾**，且提交前工作区若不干净、或 `git log` 顶部是新的 "Initialize Codex git baseline"（刚跑过自动整理），必须先读 diff 合并新内容，禁止覆盖。
- 巡检脚本（只读）：`python3 ~/.codex/skills/codex-memory-trim/scripts/collect.py`。
- 记忆快照是会话启动时一次性注入；修改只对新会话（或 `codex fork`）生效。
- 备份模板：`mkdir -p ~/.codex/backups && TS=$(date +%Y%m%d-%H%M%S) && tar czf ~/.codex/backups/memories-before-trim-$TS.tar.gz -C ~/.codex memories && cp ~/.codex/memories_1.sqlite ~/.codex/backups/memories_1-before-trim-$TS.sqlite`

## 共享红线

- 永不动 `sessions/*.jsonl`、`extensions/ad_hoc/notes/` 既有文件内容（note 只能新增或按用户原话修订）、`.git` 内部对象（正常 commit 除外）。
- 禁用 `codex debug clear-memories`（全量重置）。整理任务（`collect.py` 中 consolidate_global）运行中不写文件。
- 动手前必备份，结束必提交：`cd ~/.codex/memories && git add -A && git -c user.name="Codex" -c user.email="noreply@openai.com" commit -m "<一句话>"`，收尾 `git status --short` 必须为空。
- 本 skill 自身按效率优先执行：单次完成，不循环重复校验。
