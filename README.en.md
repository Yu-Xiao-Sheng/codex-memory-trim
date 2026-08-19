# codex-memory-trim

A skill that puts Codex's global memory on a periodic diet: detect duplicates, prune stale threads, compress verbose entries, and add custom global rules through a safe channel.

[中文版（默认）](README.md) · Both READMEs are maintained together; update both when changing either.

## Why this exists

Have you noticed your Codex getting slower and more verbose the longer you use it? You hand it a simple request, and it starts by digging through a pile of old rules — this needs verification first, that needs an approval gate, last time's lesson must be double-checked — turning a five-minute job into a process audit. Worse, sometimes it falls into a loop, grinding away at a problem that doesn't exist, burning tokens and solving nothing.

The problem usually isn't the model. It's the memory.

Codex's global memory lives in `~/.codex/memories` and grows quietly as you work. After each session it distills what it "learned" into that directory. That's a good thing in principle: new tasks can lean on past experience and skip rediscovery. But memories never retire. The acceptance workflow from a project two generations ago, the fix for an error that occurred exactly once, long-expired pipeline IDs, even sessions where nothing was actually run — they all sit in memory, and **every new task starts by searching through them**.

Here's the real trouble with old memories: they were written for old projects, old tasks, old contexts. Switch projects or task types, and those rules stop helping and start shackling. The model drags outdated constraints onto fresh requirements, runs redundant checks over and over, and eventually talks itself into a dead end. It's the same curse of knowledge humans suffer from: the more experienced you are, the harder it is to see a new problem with fresh eyes. The difference is that a person might eventually suspect they're outdated — a model won't. The rules sit in memory, get injected at the start of every session, and the model follows them faithfully every single time. Diligently inefficient.

So memory needs a periodic diet: drop the duplicates, prune the stale, shorten the verbose. This project turns that whole procedure into a skill any Codex session can execute safely, so you never have to chew through several hundred KB of Markdown by hand.

## Real-world results

The author ran three trim rounds against a production memory directory. All numbers below are from actual operations (2026-08-18 to 2026-08-19):

| Metric | Before | After 3 rounds | Change |
|---|---|---|---|
| MEMORY.md (retrieval layer) | 162 KB / 1482 lines / 32 groups | 46 KB / 474 lines / 17 groups | **-72%** |
| memory_summary.md (loaded every session) | 7.3 KB / 97 lines | 5.2 KB / 39 lines | **-60% lines** |
| raw_memories.md (consolidation input) | 340 KB / 77 threads | 257 KB / 53 threads | -24% |
| rollout_summaries | 77 files / 528 KB | 53 files / 292 KB | -45% |
| Total memory dir (excl. .git) | ~1.1 MB | 593 KB | **-46%** |
| Threads in state DB | 79 | 55 | -30% |

Details worth calling out:

- **None of the 31 removed threads was a mistake.** Five were empty "READY" echo sessions. The rest were mostly one-off lookups, records superseded by newer versions, and "memories" from sessions where not a single command was executed. Their common trait: zero retrieval hits. The verdict comes from the `usage_count` column in the `stage1_outputs` table, so you can see exactly what you're deleting before you delete it.
- **memory_summary.md is injected into every new session.** Going from 97 lines to 40 cuts the fixed per-session overhead — and that's the number *after* adding two new global rules (efficiency-first, Superpowers gating) into it.
- **One rule used to exist in five wordings.** "Push to pre, wait for manual acceptance before touching prod" appeared in five task groups with five different phrasings. Merged into one global preference; groups now keep only domain-specific rules.
- **Memory kept growing during the trim.** Between the two nights, Codex's own consolidation added 8 new threads (new feature acceptance, incident diagnosis, and so on). The final state is the net result of "trim plus growth", with zero loss. This is routine maintenance you can rerun every few weeks, not a one-time surgery.

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

A trim must move all three layers together. Delete files without touching the DB and the next automatic consolidation syncs the content right back — wasted work. So the procedure removes the summary file, the raw section, and the DB row in one pass, then commits on the memory directory's git baseline so the trimmed state becomes the new starting point for automatic consolidation.

## Safety design

- **Backup before touching anything**: full-directory tar plus a separate sqlite copy, timestamped into `~/.codex/backups/`.
- **Read-only audit**: `collect.py` writes nothing; run it whenever.
- **git as the safety net**: the memory directory is itself a git repo; `git reset --hard` rolls back in one step.
- **Hard red lines baked into the skill**: never touch `sessions/*.jsonl` or ad-hoc notes, never use `codex debug clear-memories` (that's a full reset), never write while a consolidation job is running.

## Pitfalls we hit (all encoded into the skill's rules)

1. **Never hand-copy thread IDs.** Copying IDs from the database into scripts once produced invisible character differences that made two threads survive two deletion passes. The rule now: extract IDs programmatically from file content.
2. **Automatic consolidation races you.** The overnight pipeline rewrites memory files and resets the git baseline; blindly overwriting drops whatever it just wrote. The procedure now checks baseline state first and merges instead of overwriting when a consolidation just ran.
3. **In-flight sessions don't get smarter.** The memory snapshot is injected once at session start. After a trim, old sessions keep the old snapshot; only new sessions (or `codex fork`) pick up the changes.

## Who it's for

- Heavy Codex users whose `~/.codex/memories` has grown past a few hundred KB or whose MEMORY.md runs over a thousand lines
- Anyone watching Codex apply outdated rules, re-run redundant checks, or go in circles inside old experience
- Anyone who wants to maintain global rules deliberately instead of repeating "remember this" in chat

## License

[MIT](LICENSE)
