#!/usr/bin/env python3
"""codex-memory-trim: read-only audit of Codex native memories.

Reports sizes, per-thread usage stats, orphan summaries, reference integrity,
three-layer consistency, consolidation job status, and git baseline cleanliness.
Never writes anything.
"""
import glob
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone

CODEX_HOME = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
MEM = os.path.join(CODEX_HOME, "memories")
DB = os.path.join(CODEX_HOME, "memories_1.sqlite")
USAGE_KEEP_THRESHOLD = 20  # orphan summaries above this usage are kept


def head(path, n=400):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read(n)
    except OSError:
        return ""


def count_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().count("\n") + 1
    except OSError:
        return 0


def fmt_ts(epoch):
    try:
        return datetime.fromtimestamp(int(epoch), tz=timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return "?"


def main():
    print("== Codex memories audit (read-only) ==")
    if not os.path.isdir(MEM):
        print(f"ERR: memories dir not found: {MEM}")
        sys.exit(1)

    # --- file stats ---
    print("\n[files]")
    for name in ("MEMORY.md", "memory_summary.md", "raw_memories.md"):
        p = os.path.join(MEM, name)
        size = os.path.getsize(p) if os.path.exists(p) else -1
        print(f"  {name}: {size} bytes, {count_lines(p)} lines")
    groups = 0
    mem_text = head(os.path.join(MEM, "MEMORY.md"), 10**7)
    if os.path.exists(os.path.join(MEM, "MEMORY.md")):
        with open(os.path.join(MEM, "MEMORY.md"), encoding="utf-8", errors="replace") as f:
            mem_text = f.read()
        groups = mem_text.count("# Task Group")
    print(f"  MEMORY.md task groups: {groups}")

    # --- summaries + thread ids (read from file headers, never hand-copied) ---
    files = sorted(glob.glob(os.path.join(MEM, "rollout_summaries", "*.md")))
    file_tids = {}
    for p in files:
        m = re.search(r"thread_id:\s*([0-9A-Za-z-]+)", head(p))
        if m:
            file_tids[os.path.basename(p)] = m.group(1)

    # --- raw threads ---
    raw_tids = []
    raw_path = os.path.join(MEM, "raw_memories.md")
    if os.path.exists(raw_path):
        with open(raw_path, encoding="utf-8", errors="replace") as f:
            raw_tids = re.findall(r"^## Thread `([^`]+)`", f.read(), re.M)

    # --- references from MEMORY.md ---
    refs = set(r.rstrip("`\"',.").rstrip() for r in re.findall(r"rollout_summaries/([^\s)`]+)", mem_text))
    note_refs = set(re.findall(r"extensions/ad_hoc/notes/([^\s)]+)", mem_text))
    notes_dir = os.path.join(MEM, "extensions", "ad_hoc", "notes")
    notes = set(os.listdir(notes_dir)) if os.path.isdir(notes_dir) else set()

    on_disk = {os.path.basename(p) for p in files}
    missing = sorted(refs - on_disk)
    orphans = sorted(on_disk - refs)

    # --- DB ---
    db_rows = {}
    db_selected = 0
    job_status = "unknown"
    if os.path.exists(DB):
        try:
            con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=10)
            cur = con.cursor()
            for tid, slug, uc, last, gen, sel in cur.execute(
                "SELECT thread_id, rollout_slug, usage_count, last_usage,"
                " generated_at, selected_for_phase2 FROM stage1_outputs"
            ):
                db_rows[tid] = dict(slug=slug or "", uc=uc or 0, last=last,
                                    gen=gen, sel=sel)
                db_selected += 1 if sel else 0
            try:
                (job_status,) = cur.execute(
                    "SELECT status FROM jobs WHERE kind='memory_consolidate_global'"
                    " AND job_key='global'"
                ).fetchone() or ("none",)
            except sqlite3.Error:
                pass
            con.close()
        except sqlite3.Error as e:
            print(f"\n[db] WARN cannot read {DB}: {e}")

    # --- report ---
    print("\n[consistency]")
    print(f"  summary files: {len(files)} | raw threads: {len(raw_tids)}"
          f" | DB rows: {len(db_rows)} (selected={db_selected})")
    print(f"  MEMORY.md refs: {len(refs)} | consolidate_global job: {job_status}")
    if len(files) != len(raw_tids) or len(raw_tids) != db_selected:
        print("  WARN: three layers disagree -- reconcile before trimming")
    tids_on_disk = set(file_tids.values())
    tids_raw = set(raw_tids)
    if tids_on_disk != tids_raw:
        only_files = tids_on_disk - tids_raw
        only_raw = tids_raw - tids_on_disk
        if only_files:
            print(f"  threads with file but no raw section: {sorted(only_files)}")
        if only_raw:
            print(f"  threads with raw section but no file: {sorted(only_raw)}")

    print("\n[references]")
    print(f"  missing (referenced but absent): {missing or 'OK'}")
    print(f"  note refs invalid: {sorted(note_refs - notes) or 'OK'}")

    print("\n[orphan summaries] (not referenced by MEMORY.md)")
    for f in orphans:
        tid = file_tids.get(f, "?")
        row = db_rows.get(tid, {})
        uc = row.get("uc", "?")
        verdict = "KEEP (high usage)" if isinstance(uc, int) and uc >= USAGE_KEEP_THRESHOLD else "delete candidate"
        print(f"  {f}\n    thread={tid} usage={uc} gen={fmt_ts(row.get('gen')) if row else '?'} -> {verdict}")

    print("\n[lowest-usage referenced threads] (info for deeper trim)")
    ref_tids = {file_tids[f] for f in refs if f in file_tids}
    ranked = sorted(((db_rows[t]["uc"], t, db_rows[t]["slug"])
                     for t in ref_tids if t in db_rows))[:10]
    for uc, tid, slug in ranked:
        print(f"  usage={uc:<4} {slug[:60]} ({tid[:13]}...)")

    # --- git baseline ---
    print("\n[git baseline]")
    try:
        dirty = subprocess.run(["git", "-C", MEM, "status", "--porcelain"],
                               capture_output=True, text=True, timeout=15)
        n_dirty = len([l for l in dirty.stdout.splitlines() if l.strip()])
        log = subprocess.run(["git", "-C", MEM, "log", "--oneline", "-3"],
                             capture_output=True, text=True, timeout=15)
        print(f"  dirty entries: {n_dirty}")
        for line in log.stdout.strip().splitlines():
            print(f"  {line}")
        if n_dirty:
            print("  NOTE: workspace dirty -- consolidation may have just run;"
                  " read the diff and merge before any overwrite")
    except Exception as e:
        print(f"  WARN git check failed: {e}")

    print("\n[db zero/low-usage threads] (<3 usages, any age)")
    for tid, row in sorted(db_rows.items(), key=lambda kv: kv[1]["uc"]):
        if row["uc"] < 3:
            print(f"  usage={row['uc']} gen={fmt_ts(row['gen'])} {row['slug'][:55]} ({tid[:13]}...)")

    print("\ndone. Nothing was modified.")


if __name__ == "__main__":
    main()
