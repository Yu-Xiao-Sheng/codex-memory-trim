# 子技能：add-global —— 添加自定义全局记忆

把用户口述的规则/偏好写入全局记忆，立即对新会话生效（不等自动整理）。

## 判定范围（先做这一步）

- 规则是否**全局**（适用于所有 cwd）？是 → 走本流程。若只针对某个项目 → 应写入该项目的 AGENTS.md 或对应任务组，告知用户后改走项目路径，不污染全局。
- 与现有全局偏好冲突？→ 按"直接修改记忆原始文档"原则**改写旧条目**指向新规则，不叠加互相矛盾的规则。

## 流程

1. 共享前置：备份、确认 git 基线干净（见 SKILL.md；本操作不改 DB，无需处理整理竞争以外的内容）。
2. **创建 ad-hoc note**（权威来源通道）：
   ```bash
   TS=$(date +%Y%m%d-%H%M%S)
   $EDITOR ~/.codex/memories/extensions/ad_hoc/notes/$TS-<slug>.md
   ```
   格式：`# 标题` + 要点列表。用户给了原话就**原样保留原话**（可加最小限度的边界澄清条目，但不得替用户改写语义）；从描述起草时先给用户过目再落盘。
3. **立即传播**（不等下次整理）：
   - `memory_summary.md` 的 `## User preferences` 加一条，句尾标 `[ad-hoc note]`，与同类规则放一起；
   - `MEMORY.md`：已有匹配的任务组就并入；否则新建小任务组（`# Task Group: <规则名>` + `applies_to: global` + rollout_summary_files 指向该 note，`thread_id=ad-hoc-$TS-<slug>` + 偏好/知识小节），全部标注 `[ad-hoc note]`。
4. 校验：`collect.py` 的 `note refs invalid` 应为 OK。
5. git 提交（共享模板）。
6. 告知用户：进行中的会话不生效（快照时机），重要会话可 `codex fork <SESSION_ID>` 换新线程。

## 修订与废止

- 修订：按用户原话直接编辑原 note（协议允许 edit + 需再巩固），同步更新 summary/MEMORY 中派生条目。
- 废止：note 文件按协议**永不删除**；在 summary/MEMORY 中移除派生条目，note 保留作历史记录。
