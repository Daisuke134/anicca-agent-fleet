# anicca-agent-fleet

How Anicca runs a fleet of **proactive looping agents** — resident CLI workers that claim work on their own, do it, and prove it with landed artifacts. Published 2026-11-25 as part of our build-in-public research at Anicca (a research lab company working on behaviour simulation and intervention).

## The rule

> Agents are proactive looping agents. They do not wait to be delegated to.
> A monitoring result goes to the owning agent for action — never to the founder as a bare stall report.
> A resident agent that is not claiming work is by definition down, and gets repaired or replaced on the spot.
> A landed artifact on GitHub is the only proof of work. Acks, PONGs and "started" are not work.

## Architecture (connect the dots — existing pieces only)

| Piece | What it is | Role |
|---|---|---|
| GitHub (this org's ops repo) | team-outbox delegation files + `team/ACTIVITY.md` | The single source of truth every agent polls. If it is not on GitHub, it does not count. |
| [agmsg](https://github.com/fujibee/agmsg) | SQLite cross-agent messaging (existing tool by fujibee) | Same-machine agent-to-agent wake/claim notices. |
| launchd (macOS built-in) | `KeepAlive` services | Hosts the resident Mac mini workers. |
| `worker.sh` (this repo) | ~100-line bash poller | Per-engine file inbox → CLI engine → result outbox. The only custom glue. |
| OpenCode / Command Code / Gemini CLI | Existing subscription/API routes | The engines. Each worker binds one engine + one model route. |

## The worker loop

Each resident worker is a directory: `inbox/`, `outbox/`, `done/`, `logs/`.
Every 120 s the loop writes a heartbeat line, then for each task file in `inbox/`:
runs the engine in the task's workdir, writes the full engine output to
`outbox/<task>.result.md`, and moves the task to `done/`. A heartbeat that
stopped is a down lane; a task that sits in `inbox/` is an unclaimed job.

Two failure modes we hit and fixed on 2026-11-25 (measured, not guessed):

1. **Authenticated nowhere.** Both CLIs were installed but not authenticated on the worker hosts, so every run died silently. Fix: provision the team's API key (Command Code GOAT account, shared for all agents) as a `chmod 600` env file the worker sources before the auth check — no interactive login on a headless host.
2. **Headless writes need `--yolo`.** Command Code in headless mode *answers* but refuses file writes ("requires permissions. Use --yolo"). Without the flag the lane looks alive and produces nothing. With it, the claim test below passes end-to-end.

## The claim test (how we verify a lane)

A lane is alive only when this passes:

1. Drop a small **real** task (create a specific file with specific content) into the lane — via its inbox, agmsg, or launcher.
2. The lane produces the artifact, landed on GitHub.
3. Read it back from GitHub. No artifact = the lane is down, whatever its process list says.

On 2026-11-25 this test caught: a Codex lane hard-stopped by its own usage limit (resets 2026-11-30 13:42 JST, measured from the CLI's own error), a Command Code lane unauthenticated on two hosts, and an OpenCode VM run that hung for 20 minutes with zero output. It also proved four lanes live: OpenCode (Mac), Command Code (Mac + VM), Gemini (VM).

## Files

- `mac/worker.sh` — the resident worker loop (sanitized; secrets come from env files, never from the script).
- `docs/claim-test.md` — the claim-test protocol we run after every repair.

MIT licensed. Built by connecting existing tools; the glue is the contribution.
