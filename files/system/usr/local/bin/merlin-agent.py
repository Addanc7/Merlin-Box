#!/usr/bin/env python3
"""merlin-agent.py -- the Merlin box bridge daemon.

Polls the "Merlin Box" side chat for ```merlin-exec task blocks, executes
them locally on the box hardware, and posts ```merlin-result blocks back.

Stdlib only. No inbound ports -- everything goes out through muse-cli.

Trust model: the side chat is authenticated as Chris's own muse.ai session.
Anyone who can write to that thread (Chris, or Merlin) can execute commands
on this box. That is the intended design for a personal rig, not a flaw --
but it means: keep this box's login private, and never point the daemon at
a shared/public thread.

Loop-safety:
  - Only ```merlin-exec blocks are executed. Result blocks and all other
    text are ignored.
  - Every task needs an `id:`; ids are recorded in state.json and never
    executed twice (no replays after restarts).
  - The daemon's own posts start with [merlin-box] and are skipped.
"""
import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "merlin-agent", "config.json")
STATE_DIR = os.path.join(HOME, ".local", "share", "merlin-agent")
STATE_PATH = os.path.join(STATE_DIR, "state.json")
LOG_PATH = os.path.join(STATE_DIR, "agent.log")

OWN_MARKER = "[merlin-box]"
EXEC_FENCE_RE = re.compile(r"```merlin-exec\s*\n(.*?)```", re.DOTALL)
MAX_SEEN = 500


def log(msg):
    line = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass
    print(line, file=sys.stderr, flush=True)


def run_cli(*args, timeout=120):
    """Run muse-cli, return stdout. Raises on failure."""
    env = dict(os.environ)
    env["MUSE_NO_UPDATE_CHECK"] = "1"
    env["CI"] = "1"
    p = subprocess.run(
        ["muse-cli", *args],
        capture_output=True, text=True, timeout=timeout, env=env,
    )
    if p.returncode != 0:
        raise RuntimeError("muse-cli %s failed: %s" % (" ".join(args), p.stderr.strip()[-500:]))
    return p.stdout


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def normalize_messages(raw):
    """history prints JSON; shape may vary. Normalize to a list of dicts."""
    if isinstance(raw, dict):
        for key in ("messages", "history", "items", "data"):
            if isinstance(raw.get(key), list):
                return raw[key]
        return [raw]
    if isinstance(raw, list):
        return raw
    return []


def msg_id(m):
    for key in ("id", "message_id", "uuid", "msg_id"):
        if isinstance(m, dict) and m.get(key):
            return str(m[key])
    return None


def msg_text(m):
    if not isinstance(m, dict):
        return str(m)
    for key in ("text", "body", "content", "message"):
        v = m.get(key)
        if isinstance(v, str) and v:
            return v
    return json.dumps(m)[:2000]


def parse_exec_block(block):
    """Parse the inside of a ```merlin-exec fence into a task dict."""
    task_id, timeout, script_lines, in_run = None, None, [], False
    for line in block.splitlines():
        if not in_run:
            if line.startswith("id:"):
                task_id = line[3:].strip()
            elif line.startswith("timeout:"):
                try:
                    timeout = int(line[8:].strip())
                except ValueError:
                    pass
            elif line.strip() == "run: |":
                in_run = True
        else:
            script_lines.append(line)
    script = "\n".join(script_lines).strip("\n")
    if not task_id or not script:
        return None
    return {"id": task_id, "timeout": timeout, "script": script}


def cap_output(text, limit=32768):
    if len(text) <= limit:
        return text, False
    head = int(limit * 0.75)
    tail = limit - head
    cut = len(text) - limit
    return (text[:head] + "\n... [truncated %d bytes] ...\n" % cut + text[-tail:], True)


def execute(task, workdir, default_timeout):
    timeout = task["timeout"] or default_timeout
    start = time.time()
    try:
        p = subprocess.run(
            ["bash", "-c", task["script"]],
            cwd=workdir, capture_output=True, text=True, timeout=timeout,
        )
        out = (p.stdout or "") + (p.stderr or "")
        return p.returncode, time.time() - start, out, False
    except subprocess.TimeoutExpired as e:
        out = ((e.stdout or "") + (e.stderr or "") if isinstance(e.stdout, str) else "")
        out += "\n[TIMEOUT after %ds]" % timeout
        return 124, time.time() - start, out, True


def post_result(thread_id, task_id, exit_code, duration, output):
    capped, truncated = cap_output(output)
    body = (
        "%s result for task %s\n"
        "```merlin-result\n"
        "id: %s\nexit: %d\nduration_s: %.1f\ntruncated: %s\noutput: |\n%s\n```"
        % (OWN_MARKER, task_id, task_id, exit_code, duration,
           str(truncated).lower(), capped)
    )
    out = run_cli("send", body, "--thread", thread_id, "--wait", "0", timeout=120)
    try:
        sent = json.loads(out).get("sent") is True
    except ValueError:
        sent = False
    if not sent:
        raise RuntimeError("send did not confirm: %s" % out[:200])
    # Mark the thread read so it doesn't pile up unreads.
    try:
        run_cli("seen", thread_id, timeout=30)
    except RuntimeError:
        pass


def poll_once(cfg, state):
    thread_id = cfg["thread_id"]
    workdir = cfg.get("workdir") or os.path.join(HOME, "workspace")
    default_timeout = int(cfg.get("default_timeout") or 3600)
    os.makedirs(workdir, exist_ok=True)

    try:
        out = run_cli("history", "--thread", thread_id, "--limit", "30", timeout=60)
        messages = normalize_messages(json.loads(out))
    except Exception as e:
        log("poll failed: %s" % e)
        return

    if not state.get("_shape_logged"):
        keys = sorted({k for m in messages if isinstance(m, dict) for k in m.keys()})
        log("history shape: %d messages, keys=%s" % (len(messages), keys))
        state["_shape_logged"] = True

    seen = state.setdefault("seen_ids", [])
    for m in messages:
        mid = msg_id(m)
        if mid and mid in seen:
            continue
        text = msg_text(m)
        if OWN_MARKER in text:
            if mid:
                seen.append(mid)
            continue
        for block in EXEC_FENCE_RE.findall(text):
            task = parse_exec_block(block)
            if not task:
                log("malformed exec block in msg %s, skipping" % mid)
                continue
            if task["id"] in seen:
                continue
            seen.append(task["id"])
            # keep the seen list bounded
            del seen[:-MAX_SEEN]
            save_json(STATE_PATH, state)
            log("executing task %s (timeout %ss)" % (task["id"], task["timeout"] or default_timeout))
            code, dur, output, _timed_out = execute(task, workdir, default_timeout)
            try:
                post_result(thread_id, task["id"], code, dur, output)
                log("task %s done, exit=%d, %.1fs" % (task["id"], code, dur))
            except Exception as e:
                log("task %s executed (exit=%d) but result post failed: %s -- output in %s"
                    % (task["id"], code, e, LOG_PATH))
        if mid and mid not in seen:
            seen.append(mid)
            del seen[:-MAX_SEEN]
    save_json(STATE_PATH, state)


def main():
    log("merlin-agent starting")
    state = load_json(STATE_PATH, {})
    backoff = 30
    while True:
        cfg = load_json(CONFIG_PATH, {})
        if not cfg.get("thread_id"):
            log("no thread_id in %s -- run merlin-auth.sh, retrying in 60s" % CONFIG_PATH)
            time.sleep(60)
            continue
        try:
            out = run_cli("status", timeout=60)
            log("gateway ok")
            backoff = 30
        except Exception as e:
            log("gateway/auth problem: %s -- retrying in %ss (re-run merlin-auth.sh if cookies expired)"
                % (e, backoff))
            time.sleep(backoff)
            backoff = min(backoff * 2, 600)
            continue
        try:
            poll_once(cfg, state)
        except Exception as e:
            log("poll cycle error: %s" % e)
        time.sleep(int(cfg.get("poll_interval") or 20))


if __name__ == "__main__":
    main()
