#!/usr/bin/env bash
# setup.sh — Dragon Q8B NPU bootstrap. Works on a fresh Armbian system.
#
# Installs the bundled Qualcomm FastRPC userspace .deb packages, prepares the
# DSP environment and verifies the Hexagon v68 NPU (CDSP) is alive.
# No external apt repository is required — everything ships in this repo.
#
# Usage:  sudo bash setup.sh
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEB_DIR="$SCRIPT_DIR/debs"
readonly FIRMWARE_DEB="$(ls "$DEB_DIR"/radxa-firmware-sc8280xp_*.deb 2>/dev/null | head -n1 || true)"

log()  { printf '\n\033[1;36m[setup]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok:\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  warn:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[setup] error:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo: sudo bash setup.sh"
[[ "$(uname -m)" == "aarch64" ]] || die "an aarch64 system is required"
[[ -d "$DEB_DIR" ]] || die "debs/ directory missing — clone the full repository"

BOARD_MODEL="$(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null || true)"
if [[ "$BOARD_MODEL" != "Radxa Dragon Q8B"* ]]; then
    warn "detected board: '${BOARD_MODEL:-unknown}' — this project targets Radxa Dragon Q8B (SC8280XP / Hexagon v68)."
    warn "continuing anyway; other SC8280XP boards may work."
fi

# ---------------------------------------------------------------------------
# 1. FastRPC kernel module
# ---------------------------------------------------------------------------
log "1/5 FastRPC kernel module"
if ! lsmod | grep -q '^fastrpc '; then
    modprobe fastrpc || die "modprobe fastrpc failed — this kernel has no FastRPC support"
fi
ok "fastrpc module loaded"

# ---------------------------------------------------------------------------
# 2. Bundled FastRPC userspace packages
# ---------------------------------------------------------------------------
log "2/5 installing bundled .deb packages (FastRPC userspace)"
dpkg -i \
    "$DEB_DIR"/libadsprpc1_*.deb \
    "$DEB_DIR"/libcdsprpc1_*.deb \
    "$DEB_DIR"/libsdsp-default-listener1_*.deb \
    "$DEB_DIR"/libadsp-default-listener1_*.deb \
    "$DEB_DIR"/libcdsp-default-listener1_*.deb \
    "$DEB_DIR"/libsdsprpc1_*.deb \
    "$DEB_DIR"/fastrpc_*.deb \
    "$DEB_DIR"/radxa-archive-keyring_*.deb
ok "fastrpc + libcdsprpc1 installed from local debs"

if ! command -v setfacl >/dev/null 2>&1; then
    apt-get install -y -qq acl >/dev/null 2>&1 || warn "acl not installed (only affects non-root DSP access)"
fi

# ---------------------------------------------------------------------------
# 3. Qualcomm DSP shells (extract-only)
#    Armbian already ships the CDSP boot firmware (armbian-firmware), and the
#    firmware package would try to overwrite those files — so we only take
#    the /usr/share/qcom DSP shells out of the .deb.
# ---------------------------------------------------------------------------
log "3/5 extracting Qualcomm DSP shells"
if [[ -f /usr/share/qcom/sc8280xp/radxa/dragon-q8b/dsp/cdsp/fastrpc_shell_3 ]]; then
    ok "already present, skipping"
else
    [[ -n "$FIRMWARE_DEB" ]] || die "radxa-firmware-sc8280xp .deb not found in debs/"
    TMPDIR_FW="$(mktemp -d)"
    dpkg-deb -x "$FIRMWARE_DEB" "$TMPDIR_FW/root"
    mkdir -p /usr/share/qcom
    cp -a "$TMPDIR_FW/root/usr/share/qcom/sc8280xp" /usr/share/qcom/
    rm -rf "$TMPDIR_FW"
    ok "DSP shells extracted to /usr/share/qcom/sc8280xp"
fi

# ---------------------------------------------------------------------------
# 4. DSP environment (runs here AND at every boot via fastrpc.service)
#    - /usr/lib/dsp symlink to the board's DSP tree
#    - soc_id bind-mount 449 -> 460 (QNN HTP refuses to init with the real 449)
# ---------------------------------------------------------------------------
log "4/5 preparing DSP environment (setup-dsp.sh)"
/usr/libexec/fastrpc/setup-dsp.sh || warn "setup-dsp.sh reported an error"
systemctl enable fastrpc.service >/dev/null 2>&1 || true
systemctl restart fastrpc.service >/dev/null 2>&1 || true
systemctl try-restart cdsprpcd.service >/dev/null 2>&1 || systemctl start cdsprpcd.service >/dev/null 2>&1 || true
ok "/usr/lib/dsp + soc_id fake in place, cdsprpcd running"

# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------
log "5/5 verification"
if grep -q 460 /sys/devices/soc0/soc_id 2>/dev/null; then
    ok "soc_id faked to 460 (required by QNN HTP; the real 449 fails with error 4000)"
else
    warn "soc_id is NOT faked to 460 — QNN HTP will fail with error 4000."
    warn "run '/usr/libexec/fastrpc/setup-dsp.sh' manually or reboot."
fi

if ls /dev/fastrpc-cdsp >/dev/null 2>&1; then
    ok "/dev/fastrpc-cdsp present"
else
    warn "/dev/fastrpc-cdsp missing — try: modprobe fastrpc"
fi

RPROC_STATES="$(cat /sys/class/remoteproc/remoteproc*/state 2>/dev/null || true)"
if [[ "$RPROC_STATES" == *running* ]]; then
    ok "CDSP remoteproc running"
else
    warn "CDSP remoteproc not running — reboot usually fixes firmware loading"
fi

echo
log "system ready. install a model and run it:"
echo "    bash scripts/install-model.sh qwen05     # Qwen2.5-0.5B, Chinese, 640 MB"
echo "    bash scripts/install-model.sh llama1b    # Llama3.2-1B, English, 1.8 GB"
echo "    bash scripts/run.sh qwen05 '你好，介绍一下你自己'"
