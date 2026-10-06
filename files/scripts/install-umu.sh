#!/usr/bin/env bash
# install-umu.sh -- bake umu-launcher into the image.
# umu-launcher (ULWGL) runs any Windows .exe through Proton, outside Steam.
# Pure-Python zipapp; pip is the universal install path. First `umu-run`
# invocation downloads UMU-Proton automatically (needs network, one time).
set -euo pipefail

python3 -m pip install --break-system-packages umu-launcher
command -v umu-run
umu-run --help >/dev/null && echo "umu-launcher ready: $(umu-run --version 2>/dev/null || echo ok)"
