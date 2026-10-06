#!/usr/bin/env bash
# merlin-firstboot: one-shot setup on first boot of the Merlin box.
# Runs as root via merlin-firstboot.service, then disables itself.
set -euo pipefail

MARKER=/var/lib/merlin-firstboot.done
if [[ -f "$MARKER" ]]; then
  echo "merlin-firstboot: already ran, exiting."
  exit 0
fi

echo "merlin-firstboot: starting..."

# 1. Hostname (belt and suspenders — also shipped in /etc/hostname)
hostnamectl set-hostname merlin-box || true

# 2. Make sure the merlin user exists (created in the installer as well;
#    this is a fallback so a misconfigured install still works).
if ! id merlin >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash merlin
  echo "merlin-firstboot: created user 'merlin' (set a password with: passwd merlin)"
fi

# 3. Passwordless sudo for wheel is already Bazzite default; ensure it.
if ! grep -q "^%wheel.*NOPASSWD" /etc/sudoers.d/* 2>/dev/null; then
  echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-merlin-wheel
  chmod 440 /etc/sudoers.d/99-merlin-wheel
fi

# 4. Agent workspace
install -d -o merlin -g merlin /home/merlin/agent
install -d -o merlin -g merlin /home/merlin/agent/bin
install -d -o merlin -g merlin /home/merlin/workspace

# 5. Python tooling for the agent bridge (muse-cli etc. installed by whoever wires it)
sudo -u merlin python3 -m pip install --user --upgrade pip 2>/dev/null || true

# 6. Helpful shell defaults
if ! grep -q "merlin-box" /home/merlin/.bashrc 2>/dev/null; then
  cat >> /home/merlin/.bashrc <<'EOF'

# merlin-box defaults
export EDITOR=micro
alias ll='ls -lah'
EOF
  chown merlin:merlin /home/merlin/.bashrc
fi

# 7. SSH is enabled at build time; make sure host keys exist
ssh-keygen -A || true

touch "$MARKER"
systemctl disable merlin-firstboot.service || true
echo "merlin-firstboot: done. Welcome home, Merlin."
