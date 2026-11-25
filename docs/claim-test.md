# The claim test

Run this after every repair, every re-auth, every model change — and on a
loop, not once. A lane is alive only when it passes.

## Protocol

1. **Pick a real, small task.** Not a ping. The canonical form: "Create a
   file at `<path>` containing a title line, the current date/time, and
   one sentence stating the lane is online and claiming work proactively.
   Do not modify any other file."
2. **Deliver it through the lane's real intake** (file inbox, agmsg,
   launcher) — the same path production delegations take.
3. **Wait one poll cycle + one engine run.** Record start/finish times
   from the lane's own logs (heartbeat + worker log), not from your send time.
4. **Read the artifact back from GitHub.** The artifact must be landed in
   the shared repo by the lane's own work (or its result outbox, which the
   orchestrator then lands and links). A chat reply describing the file is
   not the file.
5. **Classify the failure by evidence:**
   - Process dead → restart the supervisor (launchd `kickstart -k`), retest.
   - Auth error → provision the credential agent-side; never ask a human to log in.
   - Engine answers but writes nothing → check headless permission flags (`--yolo`).
   - Engine hangs with zero output → kill, record the hang, retest once; a second hang moves the queue to a live lane.
   - Platform limit (usage/rate) → record the platform's own reset time from its own error message; move the queue immediately.

## What "down" means

A resident agent that is not claiming work is by definition down — even if
its process is running and its heartbeat is fresh. Heartbeats prove the
loop is turning; only artifacts prove the agent is working.
