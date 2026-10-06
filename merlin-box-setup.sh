#!/usr/bin/env bash
# merlin-box-setup.sh — run ONCE on the Omen after installing stock Bazzite.
# Transforms a stock Bazzite install into the complete Merlin box, then reboots.
# Run as the merlin user (it will sudo where needed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SCRIPT_DIR/files/system"

if [[ ! -d "$FILES" ]]; then
  echo "ERROR: files/system/ not found next to this script."
  echo "Copy the whole merlin-box folder to the Omen (USB stick) and run from there."
  exit 1
fi

echo "==> merlin-box setup starting..."

# 1. Hostname
echo "merlin-box" | sudo tee /etc/hostname >/dev/null
sudo hostnamectl set-hostname merlin-box 2>/dev/null || true
echo "    hostname: merlin-box"

# 2. Layer extra packages onto the atomic image (idempotent, one reboot applies them)
echo "==> layering packages (tmux htop nvtop git python3-pip ssh wireguard direnv micro)..."
sudo rpm-ostree install -y --idempotent \
  tmux htop nvtop git python3-pip python3-virtualenv \
  openssh-server wireguard-tools direnv micro

# 3. Install the Merlin overlay files
echo "==> installing Merlin files..."
sudo cp "$FILES/etc/motd" /etc/motd
sudo install -Dm755 "$FILES/usr/local/bin/merlin-firstboot.sh" /usr/local/bin/merlin-firstboot.sh
sudo install -Dm644 "$FILES/etc/systemd/system/merlin-firstboot.service" /etc/systemd/system/merlin-firstboot.service
sudo install -Dm644 "$FILES/etc/systemd/user/merlin-agent.service" /etc/systemd/user/merlin-agent.service
sudo systemctl daemon-reload

# 4. Enable services (firstboot runs once on next boot, then disables itself)
sudo systemctl enable sshd merlin-firstboot.service
echo "    enabled: sshd, merlin-firstboot"

# 5. Agent workspace skeleton (firstboot also ensures this)
mkdir -p ~/agent/bin ~/workspace
echo "    workspace ready: ~/agent ~/workspace"

# 6. Bridge CLI (auth happens later, interactively, via merlin-auth.sh)
echo "==> installing muse-cli (bridge client)..."
export PATH="$HOME/.local/bin:$PATH"
if ! command -v muse-cli >/dev/null 2>&1; then
  if command -v pipx >/dev/null 2>&1; then
    pipx install muse-cli || python3 -m pip install --user muse-cli
  else
    python3 -m pip install --user muse-cli
  fi
fi
command -v muse-cli >/dev/null 2>&1 && echo "    muse-cli installed."

echo ""
echo "==> Setup complete. Rebooting in 15 seconds to apply the layered packages."
echo "    On next boot, merlin-firstboot finishes the setup automatically."
echo "    THEN run ./merlin-auth.sh (one-time: your muse.ai login + bridge start)."
echo "    (Ctrl+C to cancel the reboot)"
sleep 15
sudo systemctl reboot
