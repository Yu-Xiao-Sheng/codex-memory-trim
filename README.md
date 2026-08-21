# codex-memory-trim

<p align="center"><img src="assets/logo.png" width="160" alt="codex-memory-trim logo"></p>

A skill that puts Codex's global memory on a periodic diet: detect duplicates, prune stale threads, compress verbose entries, and add custom global rules through a safe channel.

English | [中文](README.zh.md)

## Why this exists

Have you noticed your Codex getting slower and wordier the longer you use it? I'm not guessing. A while back I handed it a long task that, by past experience with similar work, should have wrapped within 24 hours, so I left it running in the background (partly my fault; I trusted experience and never checked back). A full week later it declared failure, reporting that the very first stage was incomplete. The session history showed it "engineering" every single step according to my global memories: a trivial local startup script that wraps Podman got written, sent into open-code-review, endlessly patched against security guidelines, refined and re-refined, while the main progress went nowhere. Strictly speaking it did nothing wrong; every step followed its rules. But run every step through that gauntlet and efficiency falls off a cliff. Review-fix-review-again belongs to product releases; dev environments and local demos don't need it.

The root cause is memory. Codex's global memory grows quietly in `~/.codex/memories`, and most of it isn't added by hand; Codex writes experience there itself after every session. Reuse is good in principle, but memories never retire: the acceptance workflow from a project two generations ago, the fix for an error that occurred exactly once, sessions where nothing was even run — all sitting there, and **every new task starts by searching through them**. Old memories were written for old projects and old contexts; in a new one they turn into shackles. The model drags outdated constraints onto fresh requirements, reruns redundant checks, and talks itself into a dead end. That's the curse of knowledge. A person might eventually suspect they're outdated; a model won't. The rules get injected at the start of every session, and it follows them every single time. Diligently inefficient.

The way I see it, Codex is my second brain. And a brain, treated the way brains actually work, needs periodic unloading: input with no output just makes noise. Don't merely use it as a tool; manage it like another brain of your own, starting from accepting that this brain gets its own curse of knowledge. This project is the "managing" part: unload (clear out stale and redundant entries, tighten the verbose ones) and set rules (when to be strict, when to be fast). Both steps are baked into a skill.

![Memory on a diet: a bloated, tangled brain goes through a trimming funnel and comes out lean](assets/concept.png)

## Real-world results

I ran three trim rounds against my own production memory directory. All numbers below are from actual operations (2026-04-18 to 2026-08-19):

| Metric | Before | After 3 rounds | Change |
|---|---|---|---|
| MEMORY.md (retrieval layer) | 162 KB / 1482 lines / 32 groups | 46 KB / 474 lines / 17 groups | -72% |
| memory_summary.md (loaded every session) | 7.3 KB / 97 lines | 5.2 KB / 39 lines | -60% lines |
| raw_memories.md (consolidation input) | 340 KB / 77 threads | 257 KB / 53 threads | -24% |
| rollout_summaries | 77 files / 528 KB | 53 files / 292 KB | -45% |
| Total memory dir (excl. .git) | ~1.1 MB | 593 KB | -46% |
| Threads in state DB | 79 | 55 | -30% |

A few details:

- Of the 31 threads deleted, 5 were empty "READY" echo sessions; the rest were mostly one-off lookups, records superseded by newer versions, and "memories" from sessions where no command ever ran. The verdict was easy: zero in the `stage1_outputs` `usage_count` column — none of them had ever been retrieved.
- memory_summary.md gets injected into every new session. Going from 97 lines to 40 is overhead saved on every session, and that's after adding two new global rules to it (efficiency-first, Superpowers gating).
- "Push to pre, wait for manual acceptance before touching prod" used to exist in five different wordings across five task groups. Now it's one line in global preferences.
- Codex itself kept busy during this period: automatic consolidation added 8 new threads (feature acceptance, incident diagnosis). The final state is trim plus growth, nothing lost. Rerunning every few weeks is fine.

The skill has been in use inside my team for a while now, and the reaction has been good: the common report is that Codex gets through tasks faster.

## Beyond trimming: setting the rules

Deleting only treats the symptom; new memories keep arriving. So I used the add-global sub-skill to write one explicit rule into global memory: the full design-develop-test-QA flow applies only when the user explicitly requests it or during product feature development; everything else runs efficiency-first — implement the requirement directly, no repeated verification loops. Heavyweight workflows like Superpowers work the same way: opt-in only, never default. Plus a stop-loss: if the same problem fails twice in a row, stop and ask the user for a decision instead of retrying in infinite variations. Product repos keep their existing strict release gates; the two coexist without conflict.

That rule now sits near the top of my memory_summary.md preference list, and every new session reads it before doing anything else.

## Install

Requires bash and python3. Nothing else.

```bash
git clone https://github.com/Yu-Xiao-Sheng/codex-memory-trim.git
cd codex-memory-trim
./install.sh           # install or update into ~/.codex/skills/codex-memory-trim
./install.sh uninstall # remove it
```

Custom location: `CODEX_HOME=/path/to/codex ./install.sh`.

After installing, just say "trim codex memory" (or 中文 "精简记忆") in a new session. Or run the read-only audit directly:

```bash
python3 ~/.codex/skills/codex-memory-trim/scripts/collect.py
```

## Automatic scheduling

Let it tidy up on its own while the machine is on. Works on Linux and macOS:

```bash
./install.sh schedule daily 09:30             # every day at 09:30
./install.sh schedule weekly sat 10:00        # Saturdays at 10:00
./install.sh schedule daily 09:00 --random 2h # from 09:00, random delay up to 2h
./install.sh unschedule                       # remove
```

On Linux this installs a systemd user timer with `Persistent=true` (a run missed while the machine was off fires after the next boot; `--random` maps to `RandomizedDelaySec`). On macOS it installs a launchd LaunchAgent — launchd has no randomized delay, so `--random` randomizes the trigger time at install time. Every run backs up first, then audits; only threads that fully meet the deletion criteria get cleaned, and if nothing qualifies it touches nothing. Logs go to `~/.local/state/codex-memory-trim/auto.log`, and overlapping runs are prevented with a lock.

Two environment notes for unattended runs: if the scheduler has no `CODEX_API_KEY` in its environment, put it in `~/.config/codex-memory-trim/env` (one line `CODEX_API_KEY=...`, chmod 600) — the script sources it automatically; and codex's default sandbox treats `~/.codex` as read-only, so the script passes `--sandbox danger-full-access` — the safety rails live in the skill itself (backup-first guard, deletion criteria, git rollback).

## Three sub-skills

The main SKILL.md is a routing table that loads only the sub-skill file matching your intent, so it never bloats context.

| You say | What runs | Sub-skill |
|---|---|---|
| "trim / clean up / dedupe memory" | audit → usage stats → three-layer-consistent removal → rewrite index → git commit | `subskills/trim.md` |
| "compress memory / simplify verbose entries" | rewrite MEMORY.md group by group; symptom-cause-fix triplets become one-line lessons; long quotes capped at 10 words | `subskills/compress.md` |
| "add a global rule: X" | write an ad-hoc note (the official authoritative channel) → propagate to summary and index immediately, without waiting for the next consolidation | `subskills/add-global.md` |

The `collect.py` audit report looks like this (read-only, touches nothing):

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

Zero-usage orphans get flagged as delete candidates; high-usage ones are explicitly marked KEEP. What to delete and what to keep is on the page in front of you.

## How it works

Codex's native memory has three layers: `sessions/*.jsonl` are immutable raw evidence; `raw_memories.md` and `rollout_summaries/` are consolidation inputs re-rendered from the `memories_1.sqlite` state DB; `MEMORY.md` is the retrieval layer, and `memory_summary.md` is the snapshot injected at each new session's start.

A trim must move all three layers together. Delete files without touching the DB and the next automatic consolidation syncs the content right back; the deletion was wasted work. So the procedure removes the summary file, the raw section, and the DB row in one pass, then commits on the memory directory's git baseline so the trimmed state becomes the new starting point for automatic consolidation.

## Safety design

- Backup before touching anything: full-directory tar plus a separate sqlite copy, timestamped into `~/.codex/backups/`.
- Read-only audit: `collect.py` writes nothing; run it whenever.
- git as the safety net: the memory directory is itself a git repo; `git reset --hard` rolls back in one step.
- Hard red lines baked into the skill: never touch `sessions/*.jsonl` or ad-hoc notes, never use `codex debug clear-memories` (that's a full reset), never write while a consolidation job is running.

## Pitfalls we hit (all encoded into the skill's rules)

1. Never hand-copy thread IDs. Copying IDs from the database into scripts once produced invisible character differences that made two threads survive two deletion passes. The rule now: extract IDs programmatically from file content.
2. Automatic consolidation races you. The overnight pipeline rewrites memory files and resets the git baseline; blindly overwriting drops whatever it just wrote. The procedure now checks baseline state first and merges instead of overwriting when a consolidation just ran.
3. In-flight sessions don't get smarter. The memory snapshot is injected once at session start. After a trim, old sessions keep the old snapshot; only new sessions (or `codex fork`) pick up the changes.

## Who it's for

- Heavy Codex users whose `~/.codex/memories` has grown past a few hundred KB or whose MEMORY.md runs over a thousand lines
- Anyone who has watched Codex apply outdated rules, re-run redundant checks, or go in circles inside old experience
- Anyone tired of repeating "keep this in mind" in chat and wanting it to become an actual global rule

## License

[MIT](LICENSE)
