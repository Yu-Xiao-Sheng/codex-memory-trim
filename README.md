# codex-memory-trim

给 Codex 的全局记忆定期减负的 skill：检测重复、清理过期线程、压缩冗长表达，顺带提供一个安全添加自定义全局规则的通道。

[English version](README.en.md) · 两份文档同步维护，改动时请一起改。

## 为什么会有这个项目

你有没有这种感觉：Codex 用得越久，它变得越慢、越啰嗦？明明是个简单需求，它却先翻出一堆历史规矩——这个要先验证、那个要走审批、上次的教训必须核对一遍，一件小事硬是做成了流程审计。更糟的是偶尔还会陷进某个循环里，反反复复尝试解决一个根本不存在的问题，token 烧了一大把，事情没办成。

问题多半不在模型，在记忆。

Codex 的全局记忆藏在 `~/.codex/memories` 里，随着使用悄悄增长。每次会话结束，它都会把这次"学到的经验"提炼进去。这件事本身是好事：新任务先参考历史经验，能少走很多弯路。但记忆不会自己退休。上上个项目的验收流程、只出现过一次的报错处理、早已过期的流水线号、连命令都没记下来的空会话，全都躺在记忆里，而且**每一个新任务开始时都会先被检索一遍**。

旧记忆真正的麻烦在于：它是为旧项目、旧任务、旧场景写的。换一个项目、换一类任务，这些规则不但帮不上忙，反而变成枷锁。模型会拿着过时的约束去套新的需求，多余的校验做了一遍又一遍，最后把自己绕进死胡同。这和人的"知识诅咒"是同一个道理：经验越多的人，越难跳出经验去看新问题。区别在于，人多少能意识到"我可能过时了"，而模型不会——规则写在记忆里，每个新会话开局就被注入一遍，它每一次都照章办事，认真且低效。

所以记忆需要定期减负：去掉重复，清理过期，把啰嗦的表达压短。这个项目把整套减负流程固化成一个 skill，让任何一个 Codex 会话都能安全执行，不需要你手工去啃那几百 KB 的 Markdown。

## 实际效果

作者用自己的生产记忆库跑通了三轮精简，全部数据来自真实操作（2026-08-18 至 2026-08-19）：

| 指标 | 精简前 | 三轮精简后 | 变化 |
|---|---|---|---|
| MEMORY.md（检索层） | 162 KB / 1482 行 / 32 组 | 46 KB / 474 行 / 17 组 | **-72%** |
| memory_summary.md（每会话必加载） | 7.3 KB / 97 行 | 5.2 KB / 39 行 | **-60% 行数** |
| raw_memories.md（整理输入） | 340 KB / 77 线程 | 257 KB / 53 线程 | -24% |
| rollout_summaries | 77 个 / 528 KB | 53 个 / 292 KB | -45% |
| 记忆目录总量（不含 .git） | 约 1.1 MB | 593 KB | **-46%** |
| 状态库线程数 | 79 | 55 | -30% |

几个值得展开的细节：

- **删掉的 31 个线程里没有一个是冤枉的。** 有 5 个是只会回复 "READY" 的空回显会话；剩下的多是一次性查询、被新版本取代的旧记录、连命令都没执行过的"空记忆"。它们的共同点：检索命中次数为零。判断依据是状态库 `stage1_outputs` 表里的 `usage_count`，删之前看得清清楚楚。
- **memory_summary.md 是每个新会话固定注入的上下文。** 97 行压到 40 行，等于每个会话开局就省下一截；而这个数字是在往里新增了两条全局规则（效率优先、Superpowers 门控）之后的结果，净收益是实打实的。
- **同一条规则曾经以 5 种措辞存在。** "pre 部署后必须手动验收才能动 prod"这句话，散落在 5 个任务组里各有各的说法。合并成 1 条放进全局偏好，组内只留领域特定规则。
- **精简期间记忆还在正常生长。** 两晚之间 Codex 的自动整理新增了 8 个线程的新内容（新功能验收、事故诊断等）。最终态是"精简叠加新增"的净结果，零丢失。这说明它不是一次性手术，是可以每隔几周跑一次的日常维护。

## 安装

需要 bash 和 python3，没有其他依赖。

```bash
git clone https://github.com/Yu-Xiao-Sheng/codex-memory-trim.git
cd codex-memory-trim
./install.sh          # 安装或更新到 ~/.codex/skills/codex-memory-trim
./install.sh uninstall # 卸载
```

想装到别的位置：`CODEX_HOME=/path/to/codex ./install.sh`。

装完在新会话里说一句"精简 codex 记忆"就能触发；也可以直接跑只读巡检：

```bash
python3 ~/.codex/skills/codex-memory-trim/scripts/collect.py
```

## 三个子技能

主 SKILL.md 是一张路由表，按意图只加载对应的子技能文件，不给上下文添负担。

| 你说的话 | 实际执行 | 子技能 |
|---|---|---|
| "精简记忆 / 清理过期记忆 / 去重" | 巡检 → usage 统计 → 三层一致删除 → 重写索引 → git 提交 | `subskills/trim.md` |
| "压缩记忆 / 简化冗长表达" | 逐组改写 MEMORY.md，症状-原因-修复三段式压成一句教训，长引语留 ≤10 词 | `subskills/compress.md` |
| "添加全局记忆：XXX" | 写 ad-hoc note（官方权威通道）→ 立即传播到 summary 和索引，不等下次自动整理 | `subskills/add-global.md` |

`collect.py` 的巡检报告长这样（只读，不改任何东西）：

```
[files]
  MEMORY.md: 46252 bytes, 474 lines
  memory_summary.md: 5154 bytes, 39 lines
  MEMORY.md task groups: 17
[consistency]
  summary files: 53 | raw threads: 53 | DB rows: 55 (selected=55)
  MEMORY.md refs: 53 | consolidate_global job: done
[references]
  missing (referenced but absent): OK
  note refs invalid: OK
[orphan summaries] (not referenced by MEMORY.md)
  2026-07-10T02-23-06-vqG4-rae_module_independence_analysis.md
    thread=019f49d5... usage=39 gen=2026-07-24 -> KEEP (high usage)
[git baseline]
  dirty entries: 0
```

零引用的孤儿会被标成删除候选，高引用的会被明确标记保留，删什么留什么一目了然。

## 工作原理

Codex 原生记忆分三层：`sessions/*.jsonl` 是不可动的原始证据；`raw_memories.md` 和 `rollout_summaries/` 是整理输入，由状态库 `memories_1.sqlite` 重新渲染；`MEMORY.md` 是检索层，`memory_summary.md` 是每个新会话启动时注入的快照。

精简必须三层联动：只删文件不动数据库，下次自动整理会把内容同步回来，等于白干。所以流程是摘要文件、raw 段落、DB 行三处一起删，最后在记忆目录的 git 基线上提交一次，让精简后的状态成为自动整理的新起点。

## 安全设计

- **先备份再动手**：tar 全目录 + sqlite 单独备份，带时间戳存到 `~/.codex/backups/`。
- **巡检只读**：`collect.py` 不写任何文件，随手可跑。
- **git 兜底**：记忆目录本身就是 git 仓库，改坏了 `git reset --hard` 一步回滚。
- **红线写死在 skill 里**：不动 `sessions/*.jsonl`、不动 ad-hoc notes、不用 `codex debug clear-memories`（那是全量重置）、自动整理运行中不写文件。

## 踩过的坑（都写进了 skill 的执行规则里）

1. **thread id 不能手抄。** 从数据库往脚本里复制 id 时出现过隐形字符差异，导致两个该删的线程两次漏删。现在规则是 id 必须从文件内容程序化提取。
2. **自动整理会和你赛跑。** 夜间整理流程会重写记忆文件并重置 git 基线，直接覆盖会丢掉它刚写入的新内容。现在动手前必查基线状态，发现刚整理过就先合并再改。
3. **进行中的会话不会变聪明。** 记忆快照是会话启动时一次性注入的，改完记忆，老会话照旧，新会话（或 `codex fork`）才生效。

## 适合谁

- Codex 重度用户，`~/.codex/memories` 超过几百 KB 或 MEMORY.md 上千行
- 发现 Codex 开始套用过时规则、重复校验、在旧经验里打转
- 想安全地维护自己的全局规则，而不是每次都靠口头的"以后注意"

## License

[MIT](LICENSE)
