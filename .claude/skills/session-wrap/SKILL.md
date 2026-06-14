# /session-wrap

End-of-session wrap-up: capture learnings, clean up git, and record follow-ups.

## Usage

```
/session-wrap
```

## Instructions

Run three phases sequentially. Each phase requires user confirmation before writing anything.

### Phase 1: Capture session memory

Review the full conversation for: changes made, decisions reached, things learned, config discovered, troubleshooting results, and anything else worth remembering between sessions.

Draft a bullet list of these findings and present them to the user via `AskUserQuestion` for approval. Ask the user to confirm the bullets look good or suggest edits.

Once approved, append the bullets to `.claude/memory.md` under a `## YYYY-MM-DD` dated section header (use today's date). If the file doesn't exist, create it with a top-level `# Session Memory` header first. If a section for today's date already exists, append to it rather than creating a duplicate.

This file is gitignored — it's local-only and may contain sensitive operational context.

### Phase 2: Clean up git

Run these in parallel:
```bash
git status --short
```
```bash
git diff --stat
```
```bash
git diff --cached --stat
```

If the working tree is clean (no output from any command), say so and skip to Phase 3.

If there are changes, classify each changed file as:
- **Ready to commit**: completed work from this session
- **WIP**: incomplete work that should be stashed

If the classification is ambiguous for any file, ask the user via `AskUserQuestion`.

For ready-to-commit files:
1. Stage them with `git add` (name files explicitly — never use `git add -A` or `git add .`)
2. Commit with a concise imperative-mood message summarizing the session's work, ending with the co-author trailer:
   ```
   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   ```

For WIP files:
1. Stash them with a descriptive message: `git stash push -m "WIP: <description>" -- <files>`

After committing/stashing, ask the user whether to push to origin. Only push if they confirm.

### Phase 3: Record follow-ups

Review the conversation for deferred work, open issues, things that need follow-up, and future tasks.

Draft a checklist (using `- [ ]` markdown checkboxes) and present it to the user via `AskUserQuestion` for approval. Ask the user to confirm the items look good or suggest edits.

Once approved, append the items to `todo.md` (repo root) under a `## YYYY-MM-DD` dated section header. If the file doesn't exist, create it with a top-level `# Todo` header first. If a section for today's date already exists, append to it rather than creating a duplicate.

If there are no follow-ups, say so and skip creating/updating the file.

Stage and commit `todo.md` separately from the session work commit:
```
Add follow-up items from session

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

### Summary

Print a one-line-per-phase recap:
- **Memory**: what was saved (number of bullets, or "skipped")
- **Git**: what was committed/stashed/pushed (or "clean, nothing to do")
- **Todos**: what was added (number of items, or "none")

## allowed-tools

Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
