# merlin-box

Merlin's dedicated rig: the complete custom OS for the old HP Omen
(17-an012dx, i7-7700HQ, GTX 1050 Ti) — always on, always plugged in, GPU ready,
KDE Plasma desktop.

## The 10-minute path (recommended)

No building, no GitHub, no waiting. You install **stock Bazzite**, my script
does the rest.

1. Download the stock **Bazzite-nvidia** ISO from
   [bazzite.gg](https://bazzite.gg) and flash it to a USB stick.
2. Boot the Omen, install. When the installer asks, create the user **`merlin`**
   (make it an administrator). These are the credentials for the box.
3. Copy this whole `merlin-box` folder to the Omen (USB stick).
4. Open a terminal in the folder and run:
   ```
   ./merlin-box-setup.sh
   ```
   It layers the extra packages, installs all Merlin files, enables the
   services, and reboots. On the next boot, the one-shot `merlin-firstboot`
   service finishes the setup automatically and disables itself.
5. Back in the terminal, run `./merlin-auth.sh`. It installs the bridge
   client, asks you to paste your muse.ai login cookies **once** (from
   Chrome on the box — the script walks you through it), creates the
   private "Merlin Box" chat channel, and starts the bridge service.
6. Tell Merlin "the box is online". He'll run a GPU check to prove the
   loop is live.
7. Done. It's the Merlin box: hostname `merlin-box`, SSH ready, agent
   workspace at `~/agent`, GPU drivers live — and Merlin driving.

## What the setup installs

- Packages (layered via rpm-ostree): tmux, htop, nvtop, git, python3-pip,
  virtualenv, openssh-server, wireguard-tools, direnv, micro
- `sshd` enabled — key-based auth recommended
- `merlin-firstboot.service`: one-shot first-boot setup (ensures the merlin
  user, workspace dirs, SSH host keys), then disables itself
- `merlin-agent.service` (user unit, placeholder): the agent bridge slot —
  whoever wires up the muse.ai link sets the real `ExecStart`, then
  `systemctl --user enable --now merlin-agent`
- Hostname `merlin-box`, custom motd, passwordless sudo for wheel

## Agent wiring — BUILT IN

The bridge is part of the box now, not a job for later:

- `merlin-agent.py` — the daemon. Polls the private "Merlin Box" side chat
  every 20s for ```` ```merlin-exec ```` task blocks, runs them on the box
  hardware, posts ```` ```merlin-result ```` blocks back. No inbound ports.
- `merlin-auth.sh` — one-time setup: installs `muse-cli`, captures your
  muse.ai login, creates the channel, starts the service.
- `BOX_PROTOCOL.md` — the full contract: task/result format, safety model
  (no replays, no self-triggering, localhost-only), troubleshooting.

Preinstalled and ready: sshd, Python 3 + pip, `muse-cli`, `~/agent/bin`,
`tmux`/`nvtop` for long GPU jobs. `loginctl enable-linger merlin` is set
by the auth script so the bridge runs at boot with no login session.

## Advanced path: BlueBuild image

`recipes/recipe.yml` is a BlueBuild recipe for the same system as a bootable
OCI image (for GitHub Actions builds / ISO generation later). The setup script
above is the primary path; the recipe is there when you want image-based
updates.

## GPU notes

- GTX 1050 Ti (Pascal, sm_61) is still supported by current Nvidia drivers —
  stock Bazzite-nvidia carries them.
- 4GB VRAM: fine for the CivNexus6 cooker and lighter CUDA work. TRELLIS's
  prebuilt CUDA extensions were compiled without sm_61 — rebuilding them for
  Pascal is the box's first overnight job (see MERLIN_BOX_SPEC.md).
- `nvtop` is installed for keeping an eye on it.
