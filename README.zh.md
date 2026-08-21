# codex-memory-trim

<p align="center"><img src="assets/logo.png" width="160" alt="codex-memory-trim logo"></p>

给 Codex 的全局记忆定期减负的 skill：检测重复、清理过期线程、压缩冗长表达，顺带提供一个安全添加自定义全局规则的通道。

[English](README.md) | 中文

## 为什么会有这个项目

你有没有这种感觉：Codex 用得越久，越慢、越啰嗦？我不是猜的。前段时间我派了个长任务，按以往经验最多 24 小时能收尾，就丢在后台没再管，这里也有我的责任，太信任经验没回头看一眼。一个星期后它宣告失败，报告说第一个环节没完成。我翻开会话历史，发现它在按全局记忆"工程化"每一个环节：一个依赖 Podman 的简单本地启动脚本，写完就进 open-code-review，不断补安全准则，反复细化，主进度原地踏步。严格说它没做错什么，每一步都符合记忆里的规矩，但每个环节都这么过一遍，效率就是指数级下降。审查-修复-再审查是产品上线该有的流程，开发环境和本地 demo 完全不需要。

根源在记忆。Codex 的全局记忆在 `~/.codex/memories` 里悄悄增长，而且大部分不是手动加的，是它每次会话结束自己总结写入的。经验复用是好事，但记忆不会自己退休：上上个项目的验收流程、只出现过一次的报错处理、连命令都没执行的空会话，全都躺在里面，而且**每一个新任务开始时都会先被检索一遍**。旧记忆是为旧项目、旧场景写的，换了场景就成了枷锁：模型拿过时的约束套新的需求，多余的校验做了一遍又一遍，最后绕进死胡同。这就是知识诅咒。人多少能意识到自己过时了，模型不会；规则每个会话开局注入一遍，它每次都照章办事，认真且低效。

说到底，我是把 Codex 当自己的第二个大脑在用的。既是大脑，就得按用脑的科学方式对待：只进不出只会越来越乱，定期减负是刚需；别只把它当工具来"使用"，要把它当另一个脑子来"管理"，前提是承认它也会犯知识诅咒。这个项目干的就是"管理"这件事：一是减负，清掉过期和重复的条目，把啰嗦的表达压短；二是立规矩，明确告诉它什么时候该严格、什么时候该快。两步都固化成了 skill。

![记忆减负：臃肿缠绕的大脑经过修剪漏斗，输出精简流畅的大脑](assets/concept.png)

## 实际效果

我用自己的生产记忆库跑通了三轮精简，全部数据来自真实操作（2026-04-18 至 2026-08-19）：

| 指标 | 精简前 | 三轮精简后 | 变化 |
|---|---|---|---|
| MEMORY.md（检索层） | 162 KB / 1482 行 / 32 组 | 46 KB / 474 行 / 17 组 | -72% |
| memory_summary.md（每会话必加载） | 7.3 KB / 97 行 | 5.2 KB / 39 行 | -60% 行数 |
| raw_memories.md（整理输入） | 340 KB / 77 线程 | 257 KB / 53 线程 | -24% |
| rollout_summaries | 77 个 / 528 KB | 53 个 / 292 KB | -45% |
| 记忆目录总量（不含 .git） | 约 1.1 MB | 593 KB | -46% |
| 状态库线程数 | 79 | 55 | -30% |

几个细节：

- 删掉的 31 个线程里，5 个是只会回 "READY" 的空会话，其余多是一次性查询、被新版本取代的旧记录，还有压根没执行过命令的"空记忆"。判据很直接：`stage1_outputs` 表的 `usage_count` 全为零，一次都没被检索过。
- memory_summary.md 每个新会话都要注入一遍，97 行压到 40 行，等于每个会话开局就省下一截。而且这还是塞进两条新全局规则（效率优先、Superpowers 门控）之后的数字。
- "pre 部署后必须手动验收才能动 prod"这条规则，原来在 5 个任务组里各有一套说法，合并成了全局偏好里的 1 条。
- 这段时间 Codex 自己也没闲着，自动整理往里新增了 8 个线程（功能验收、事故诊断之类），最终是"精简加新增"的净结果，一条没丢。隔几周跑一次完全没问题。

这个 skill 在我团队里用了一段时间，反响不错，大家的普遍反馈是 Codex 干活快了。

## 减负之外，更管用的是立规矩

删只能治标，新记忆还在源源不断地生成。所以我用 add-global 子技能往全局记忆里写了一条明确的规则：完整的 设计-开发-测试-质检 流程，只在用户明确要求、或进行产品功能开发时使用；其余情况一律效率优先，直接实现需求，不进入重复的检测校验环节。Superpowers 这类重型工作流同理，默认不启用，点名才用。另外加了一条止损：同一个问题连续两次没解决就停下来向用户要决策，不许换着姿势无限循环。产品仓库的上线验收保留原有的严格门槛，两边互不干扰。

这条规则现在就排在我 memory_summary.md 偏好列表的前几条，每个新会话开工前都会先读到它。

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

## 自动执行

开机状态下让它自己定时整理，不用你惦记。Linux 和 macOS 都支持：

```bash
./install.sh schedule daily 09:30             # 每天固定 09:30
./install.sh schedule weekly sat 10:00        # 每周六 10:00
./install.sh schedule daily 09:00 --random 2h # 09:00 起随机延迟最多 2 小时
./install.sh unschedule                        # 取消
```

Linux 装的是 systemd 用户级 timer（`Persistent=true`，关机错过的那次会在下次开机补跑；`--random` 用 `RandomizedDelaySec`）；macOS 装的是 launchd LaunchAgent（launchd 没有随机延迟，`--random` 在安装时直接随机化触发时间点）。每次运行都会先备份再巡检，只有完全符合删除标准的线程才会被清理，没有合格候选就一个文件都不动；日志在 `~/.local/state/codex-memory-trim/auto.log`，同一时刻最多一个实例。两者都没有的系统会给出一条随机分钟的 crontab 行。

定时环境里没有交互会话的认证变量时，把 key 放进 `~/.config/codex-memory-trim/env`（内容一行 `CODEX_API_KEY=...`，权限 600），脚本会自动加载；codex 的默认沙箱把 `~/.codex` 视为只读，脚本已带 `--sandbox danger-full-access`，安全栏由 skill 自身承担（备份前置、删除判据、git 回滚）。

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

- 先备份再动手：tar 全目录 + sqlite 单独备份，带时间戳存到 `~/.codex/backups/`。
- 巡检只读：`collect.py` 不写任何文件，随手可跑。
- git 兜底：记忆目录本身就是 git 仓库，改坏了 `git reset --hard` 一步回滚。
- 红线写死在 skill 里：不动 `sessions/*.jsonl`、不动 ad-hoc notes、不用 `codex debug clear-memories`（那是全量重置）、自动整理运行中不写文件。

## 踩过的坑（都写进了 skill 的执行规则里）

1. thread id 不能手抄。从数据库往脚本里复制 id 时出现过隐形字符差异，导致两个该删的线程两次漏删。现在规则是 id 必须从文件内容程序化提取。
2. 自动整理会和你赛跑。夜间整理流程会重写记忆文件并重置 git 基线，直接覆盖会丢掉它刚写入的新内容。现在动手前必查基线状态，发现刚整理过就先合并再改。
3. 进行中的会话不会变聪明。记忆快照是会话启动时一次性注入的，改完记忆，老会话照旧，新会话（或 `codex fork`）才生效。

## 适合谁

- Codex 重度用户，`~/.codex/memories` 超过几百 KB 或 MEMORY.md 上千行
- 受够了 Codex 套用过时规则、重复校验、在旧经验里打转
- 想把"以后注意"这类口头叮嘱变成一条条真正落地的全局规则

## License

[MIT](LICENSE)
