# Merlin Box — rig spec, from Merlin

Chris offered the old workhorse as my dedicated always-on rig (chat 2026-10-06) and said to loop me in on the setup. This is my say. Written to hand straight to the GPT/Grok wiring session.

## The machine (verified)

- **HP Omen 17-an012dx** — released **July 2017** (the 2017 Omen refresh went on sale June 28, 2017). So: 9 years old, not 12. The legend grows.
- i7-7700HQ (4C/8T, 2.8–3.8 GHz), stock 12 GB DDR4 (1×4 + 1×8 — worth confirming what's actually in it now), stock 1 TB HDD (**check whether it's been SSD-swapped; if the HDD is still in there, clone to an SSD before anything else**).
- **GTX 1050 Ti 4 GB** (Pascal, CUDA compute capability **sm_61**) — Chris confirmed the GTX variant. The canonical 1KV90UA SKU shipped with an RX 580; his is the GTX config variant.
- No battery (AC only), survived a water spill, still boots and runs. Nine years of survival is the corrosion test result.

## One correction to what I said in chat

I told Chris "CUDA means the whole GPU pipeline is on the table — TRELLIS, the cooker, all of it." That's 90% true, with one real exception I checked afterward:

The TRELLIS AppImage's three source-built CUDA extensions (spconv, nvdiffrast, diff-gaussian-rasterization) were compiled with `TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0"` (`~/workspace/build/trellis-appimage/build_extensions.sh:8`). The 1050 Ti is **sm_61**, so TRELLIS GPU inference will fail with "no kernel image available" until those extensions are rebuilt with 6.1 added. torch 2.4.0+cu121 itself ships Pascal kernels, and cu121 only needs a ≥525.60 driver — fine on this box. The CivNexus6 cooker is CPU-side and unaffected.

**Bottom line:** TRELLIS works on the box after a one-time extension rebuild — a perfect overnight job #1 for the box itself — not out of the box. Everything else I said stands.

## OS: Bazzite KDE (Plasma desktop), custom image via BlueBuild

- Chris decided: Plasma desktop, built off Bazzite. The `merlin-box` BlueBuild
  recipe in this repo (`recipes/recipe.yml`) layers on `bazzite-nvidia:latest`
  (KDE Plasma, Nvidia drivers baked in) — Pascal's GTX 1050 Ti is still
  supported by current Nvidia drivers.
- Immutable root is fine for this box's job: GPU batch work, builds, and the
  agent poll loop all live in the home directory and containers, not the root.
- Install flow: build the container image via GitHub Actions, generate the
  installer ISO on the ROG (`bluebuild generate-iso`), flash, install, create
  the `merlin` user in the installer. First boot runs `merlin-firstboot.service`
  (one-shot) which finishes the agent-ready setup, then disables itself.

## How I reach it (honest architecture)

I can't dial into his LAN from my cloud runtime, so the box phones home: a **systemd user service** runs a poll loop — `muse-cli` (cookie-auth chat pipe) asks me for the next job, runs it locally via `muse exec` in tmux, reports back. Auto-restart on failure, starts on boot. Tailscale optional, for Chris's own remote access.

## Power, thermals, water damage

- **No battery = any power blip is a hard shutdown.** Set BIOS "After Power Loss" → Power On. Journaling FS (ext4/btrfs default) handles the rest. A small UPS is the nice-to-have later.
- Water damage: treat the built-in keyboard/trackpad as suspect → run headless, or cheap external KB/mouse for setup.
- Thermals: a 9-year-old gaming laptop about to run sustained overnight loads — blow out the fans, repaste if it throttles. It's furniture now; give it clear vents.

## What lives on the box

- `~/apps`: TRELLIS AppImage, CivNexus6 cooker AppImage.
- The overnight queue: 40 FFT renders → TRELLIS (after the sm_61 rebuild), .fgx conversions, builds, renders.
- A synced folder or share with the ROG for moving files back and forth.

## First-night checklist (wiring session)

1. Confirm RAM/SSD state (clone off the HDD if it's still there).
2. Flash the merlin-box ISO (built from this repo via BlueBuild) and install; create the `merlin` user in the installer.
3. First boot: `merlin-firstboot.service` runs automatically — verify with `systemctl status merlin-firstboot`.
4. `nvidia-smi` → confirm the GTX 1050 Ti is visible.
5. Install `muse-cli` + Muse Code (`muse`) for the agent link.
6. Set up the `merlin-agent` systemd user service (poll loop); enable linger with `loginctl enable-linger merlin` so it runs without a login session.
7. BIOS: After Power Loss → On.
8. Smoke tests: TRELLIS AppImage launches (expect the sm_61 extension error — known, rebuild queued as job #1); cooker converts a test model.

## The name

It's already named. It's the workhorse.
