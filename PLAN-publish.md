# PLAN-publish.md — Addendum: Harness Selection

Insert as a new section after the **Architecture (target state)** block and before **Session P1**. This pins the orchestration layer for the five components, which the original plan left as an implementation detail.

---

## Harness selection (read before P1)

The five components (watcher, draft agent, self-checks, verification gate, publisher) need an orchestration layer. This section records the decision and the reasoning, so it survives as an ADR-style artifact rather than an undocumented default.

**Decision: Hermes (Nous Research) as the orchestration harness. OpenClaw considered and rejected.**

### Why a harness at all, and why this one

The harness was evaluated against the six-question framework in `best-of-Agent-Harnesses/how-to-pick-a-harness`. Answers for this tier:

1. **Job** — always-on personal agent: watch notes, draft, gate, publish. On the named-candidate list.
2. **Adopt how much** — lowest tier that solves the job. The pipeline spine is modest; the harness must not become a second system to maintain. Hermes is lean (skills mostly self-generated; checkpoint/rollback built in) rather than a sprawling platform.
3. **How much rope** — this is decisive. The governing principle requires a HARD human gate before publish: step- or checkpoint-gated, explicitly NOT headless-by-default behavior. Hermes's no-heartbeat + `wakeAgent` script gate + per-domain isolation matches this natively. The publish action lives in its own restricted domain behind a permission prompt.
4. **Recovery** — low stakes; a missed poll just delays a draft. Hermes's checkpoint/rollback is a bonus, not a requirement here.
5. **Tokens** — post-June-15-2026, programmatic/third-party usage draws from a separate non-rollover Agent SDK credit pool, billed at API rates. Cost is usage-shape, not harness choice. Mitigations are mandatory regardless of harness (see Cost discipline below).
6. **Walk away** — MIT license, open formats, provider-flexible (Hermes most natively, open-weights being Nous's thesis). Audit log stays a first-class exportable artifact independent of the harness.

### Why NOT OpenClaw (firsthand + documented)

Prior hands-on experience: OpenClaw's permissiveness was not trustworthy for a named-byline publishing agent. The comparison confirms this is by design, not a bug:
- OpenClaw security posture: relaxed by default ("free reign"); user sandboxes it themselves.
- Heartbeat model: background events inject into the main conversation, against unbounded accumulating memory.

For a harness whose one load-bearing control is "drafts autonomously, never publishes autonomously," a porous-by-default boundary between background events and the live conversation works against the gate. Hermes inverts each default toward isolation: restrictive by default, sandboxed cron isolated from the main conversation, confined script locations, per-domain isolation.

### Honest counterweights (do not omit from the writeup)

- **Stability is partly an age artifact.** Hermes has shipped ~6 releases to OpenClaw's ~82; it has not lived long enough to accumulate the breakage OpenClaw is criticized for. Its stability record is partly youth, not proven durability.
- **The learning loop is double-edged.** Hermes can turn a recurring task into a reusable skill unprompted — but bad decisions get learned too and are hard to scrape back out.

### Constraints this imposes on the build

- **C-H1: The verification gate must sit OUTSIDE anything the learning loop can modify.** The gate is the one component that must never be self-rewritten. Pin it in a confined script location; do not let it become a learned skill.
- **C-H2: Cost discipline is mandatory, in priority order — (1) wake less:** the notes-watcher is a deterministic `wakeAgent` script that only invokes a model on an actual notes change; **(2) route by tier:** background/watch work uses a cheap or open-weight model, drafting uses a mid-tier model, never a frontier model on a schedule; **(3) slim the tool list:** the draft agent gets only the tools it needs, since large registries tax every turn.
- **C-H3: Administer from CLI/TUI, not chat.** Several Hermes commands are CLI/TUI-only. This harness lives on the cluster; do not assume phone-only administration.

### Portfolio note (feeds the Part 5 writeup)

The decision itself is thesis-aligned material: "used OpenClaw, distrusted its permissiveness for a named-byline agent, moved to the discipline-optimized harness — here's the threat model that drove it" is attestation-without-verification applied to the tooling choice, not just the pipeline. Stronger than picking by star count.