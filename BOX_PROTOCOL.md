# Merlin Box protocol v1 — how Merlin drives the box

The box runs `merlin-agent.py` (user systemd service). It polls a private
**"Merlin Box" side chat** on Chris's muse.ai account and executes task
blocks posted there. No inbound ports; the box only ever calls out.

## The channel

- Side chat titled **"Merlin Box"**, created once by `merlin-auth.sh`.
- Thread id lives in `~/.config/merlin-agent/config.json` on the box.
- Poll interval: 20s. Auth: Chris's `muse-cli` cookies
  (`~/.config/muse-cli/cookies.txt`, mode 600). When cookies expire,
  re-run `merlin-auth.sh` step 2.

## Task format (what Merlin posts)

Merlin — this means you — post a fenced block in the channel:

````text
```merlin-exec
id: <uuid, you generate it>
timeout: <seconds, optional, default 3600>
run: |
  <bash script, non-interactive>
```
````

Rules for posting tasks:
- Only post a task block when Chris asked for box work, or when continuing
  a box job whose earlier result just came back.
- One job per block; chain multi-step jobs by reading each `merlin-result`
  before posting the next block.
- Commands must be non-interactive (no prompts, no sudo password reads —
  the merlin user has passwordless sudo).
- Prefer absolute paths. Workdir defaults to `~/workspace`.
- Keep each command's output modest; results are capped at 32KB
  (head + tail with a truncation note).

## Result format (what the box posts back)

````text
[merlin-box] result for task <id>
```merlin-result
id: <id>
exit: <code, 124 = timeout>
duration_s: <float>
truncated: <true|false>
output: |
  <stdout+stderr, capped>
```
````

Posted with `send --thread <id> --wait 0` (fire-and-forget — the box does
not wait for a reply). Read results in the channel before the next step.

## Safety model

- **Trust root:** the side chat. It is authenticated as Chris's own muse.ai
  session. Anyone able to write there (Chris, Merlin) can exec on the box.
  Never point the daemon at a shared or public thread.
- **No replays:** task ids are recorded in
  `~/.local/share/merlin-agent/state.json` and never executed twice,
  even across restarts.
- **No self-triggering:** the daemon's own posts begin with `[merlin-box]`
  and are skipped by the poller. Only `merlin-exec` fences execute;
  `merlin-result` fences and plain chat never do.
- **Blast radius:** localhost only. The daemon opens no ports and accepts
  no connections. Timeouts kill runaway commands (exit 124).
- **Audit:** every cycle logs to `~/.local/share/merlin-agent/agent.log`
  and the systemd journal (`journalctl --user -u merlin-agent`).

## Bringing it online (on the box)

1. `./merlin-box-setup.sh` → reboot (base OS + packages).
2. `./merlin-auth.sh` → paste the muse.ai cookie line once → channel
   created, service started.
3. Chris tells Merlin "the box is online". Merlin verifies with a task:
   ````text
   ```merlin-exec
   id: hello-box
   timeout: 30
   run: |
     hostname && nvidia-smi --query-gpu=name,memory.total --format=csv
   ```
   ````
   The `merlin-result` post confirms the loop is live.

## Troubleshooting

- `systemctl --user status merlin-agent` / `journalctl --user -u merlin-agent -f`
- `~/.local/share/merlin-agent/agent.log` — includes the detected
  `history` JSON shape on first poll (for gateway drift).
- `muse-cli status` — if this fails, cookies expired; re-run `merlin-auth.sh`.
- If whole classes of `muse-cli` calls start failing at once, the gateway
  protocol drifted (see muse-cli's docs/PROTOCOL.md) — update `muse-cli`
  with `muse-cli update`, don't guess at the protocol.
