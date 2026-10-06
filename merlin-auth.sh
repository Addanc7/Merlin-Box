#!/usr/bin/env bash
# merlin-auth.sh -- one-time bridge auth for the Merlin box.
# Run AFTER merlin-box-setup.sh + reboot. Interactive: needs Chris.
#
# What it does:
#   1. Installs muse-cli (the terminal pipe to Merlin's muse.ai agent).
#   2. Captures Chris's muse.ai login cookies (one paste, stored mode 600).
#   3. Creates the private "Merlin Box" side chat = the command channel.
#   4. Enables linger + starts the merlin-agent bridge service.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

echo "==> 1/4 installing muse-cli..."
if ! command -v muse-cli >/dev/null 2>&1; then
  if command -v pipx >/dev/null 2>&1; then
    pipx install muse-cli
  else
    python3 -m pip install --user muse-cli
  fi
fi
muse-cli --help >/dev/null && echo "    muse-cli ready: $(muse-cli --version 2>/dev/null || echo ok)"

echo "==> 2/4 checking muse.ai login..."
if ! muse-cli status >/dev/null 2>&1; then
  echo ""
  echo "    The bridge needs your muse.ai login, once. On THIS box:"
  echo "      1. Open Chrome, go to https://muse.ai/ and log in."
  echo "      2. Press F12 -> Application tab -> Cookies -> https://muse.ai"
  echo "      3. Copy the cookies as ONE line, like:"
  echo "           hatch_sess=VALUE; other_cookie=VALUE"
  echo ""
  echo -n "    Paste that line (hidden) and press Enter: "
  read -rs COOKIES || COOKIES=""
  echo ""
  if [[ -z "${COOKIES// }" ]]; then
    echo "    Nothing pasted. Run this script again when ready."
    exit 1
  fi
  mkdir -p ~/.config/muse-cli
  printf '%s\n' "$COOKIES" > ~/.config/muse-cli/cookies.txt
  chmod 600 ~/.config/muse-cli/cookies.txt
  COOKIES="x"
  unset COOKIES
  echo "    cookies saved (mode 600)."
fi
muse-cli status >/dev/null && echo "    login verified."

echo "==> 3/4 creating the Merlin Box channel..."
mkdir -p ~/.config/merlin-agent
if [[ ! -f ~/.config/merlin-agent/config.json ]]; then
  echo "    creating side chat 'Merlin Box'..."
  RAW="$(muse-cli session-start --title "Merlin Box")"
  THREAD_ID="$(printf '%s' "$RAW" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if isinstance(d, dict):
    for k in ('session_id','id','thread_id','sessionId'):
        if d.get(k):
            print(d[k]); break
")"
  if [[ -z "$THREAD_ID" ]]; then
    echo "    Could not read the new chat id. Raw output:"
    printf '%s\n' "$RAW"
    echo "    Paste the chat id and press Enter: "
    read -r THREAD_ID
  fi
  python3 - "$THREAD_ID" <<'EOF'
import json, os, sys
tid = sys.argv[1].strip()
cfg = {
    "thread_id": tid,
    "poll_interval": 20,
    "workdir": os.path.expanduser("~/workspace"),
    "default_timeout": 3600,
}
os.makedirs(os.path.expanduser("~/.config/merlin-agent"), exist_ok=True)
with open(os.path.expanduser("~/.config/merlin-agent/config.json"), "w") as f:
    json.dump(cfg, f, indent=2)
print("    channel saved.")
EOF
else
  echo "    channel already configured."
fi

echo "==> 4/4 starting the bridge service..."
loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER" || true
systemctl --user daemon-reload
systemctl --user enable --now merlin-agent.service
sleep 2
systemctl --user is-active merlin-agent.service >/dev/null \
  && echo "    merlin-agent is RUNNING." \
  || { echo "    service did not start -- check: journalctl --user -u merlin-agent -e"; exit 1; }

echo ""
echo "==> The box is listening. Tell Merlin 'the box is online' and he'll take it from there."
echo "    Logs: journalctl --user -u merlin-agent -f   and   ~/.local/share/merlin-agent/agent.log"
