Meet My AI "Staff" -

As I mentioned recently, I've been diving deep into Agentic AI tooling (specifically Hermes) for actual daily productivity—and, frankly, just making up absurd tasks to see where the boundaries are.

Here is my current direct-report roster. None of them require a corner office, none take PTO, and the whole org chart runs with zero corporate drama.
They all report to Supe, the supervisor. She's the master orchestrator—keeping the crew coordinated, handing out assignments, and making sure the entire machine runs smoothly. It's an enterprise roster that would make any HR department sweat:

 - Doc — My personal physician, minus the 45-minute waiting room magazine read. Analyzes sleep metrics, processes Garmin data, and delivers the precise health nagging I'd otherwise ignore. 24/7 house calls, zero copay.
 - Fred — The CFO. Audits every card swipe, flags suspicious transactions, and translates weekly cash flow into plain English. The only accountant who doesn't bill by 15-minute increments.
 - Mike — Executive recruiter and career intel operative. Honestly, he probably knows where my next role is before the hiring manager does. Slightly terrifying, highly useful.
 - Ted — Tech researcher. AI models, datacenter infrastructure, or whatever hyper-specific rabbit hole I throw him down at midnight. He reads the documentation so I don't have to.
 - Sven — Fitness Director. Cycling, trail running, Strava telemetry. He syncs the rides, analyzes the wattage, and instantly detects when a "rest day" was actually just laziness. (He always knows.)
 - Sal — Fleet mechanic. Tracks maintenance, diagnoses weird engine noises, and has never once said "it's probably fine." Because it usually wasn't.
 - Gwen — General Counsel. Deciphers fine print, reviews contracts, and answers the age-old question, "Can they actually do that?" (The answer is almost always no.)
 - Atlas — Web developer & digital designer. She turns raw ideas into functional web deployments faster than a traditional dev team can schedule a discovery call.

No payroll. No 401(k) match. No passive-aggressive Slack messages. Just a hyper-specialized team that never sleeps, never calls in sick, and only asks for one thing in return: tokens.

Speaking of my previous rant on traditional resume formatting, I had Atlas build a custom webpage to host my executive summary and offer direct resume downloads. You can check it out live at https://batesfam.net.

The wild part? She built and deployed the whole thing entirely through natural language prompts via Telegram on my phone during about 20 minutes of back-and-forth while I was on the move.

---

## Deployment Status

### Deployed (Wave 1)

| Agent | Namespace | Telegram Bot | Model | Status |
|-------|-----------|-------------|-------|--------|
| Darwin | hermes-darwin | @Darwin_briefing_bot | claude-opus-4-6 (Anthropic) | Running |
| Carson | hermes-carson | @carson_ha_bot | claude-opus-4-6 (Anthropic) | Running (HA integration blocked) |

### Architecture

- Shared vendored Helm chart at `k8s/hermes/chart/`
- Per-agent values at `k8s/hermes-<name>/values.yaml`
- Per-agent ArgoCD Application at `k8s/argocd/apps/hermes-<name>.yaml`
- Per-agent namespace with baseline PSA enforce, restricted warn/audit
- ExternalSecrets via 1Password (ClusterSecretStore `onepassword`)

### Open Items

- **Carson HA integration (S4 blocker):** Tirith (Hermes security scanner)
  blocks Carson's terminal-based curl calls to the HA REST API because HA's
  cluster-internal service uses plain HTTP and Tirith flags HTTP URLs +
  pipe-to-interpreter patterns as HIGH severity. This is working as intended
  (Tirith is a valuable guardrail). To unblock Carson, deploy a Home Assistant
  MCP server (or Hermes plugin) that provides native HA tools — API calls
  inside the tool implementation bypass Tirith's terminal scanning. Investigate
  existing HA MCP servers before building one.

### Future Agents

| Agent | Role | Notes |
|-------|------|-------|
| Doc | Health / Garmin analyst | |
| Fred | CFO / finance | |
| Mike | Recruiter / career intel | |
| Ted | Tech researcher | |
| Sven | Fitness / Strava | |
| Sal | Fleet mechanic | |
| Gwen | General counsel | |
| Atlas | Web developer | |
| Supe | Supervisor / orchestrator | Depends on multi-agent coordination |
