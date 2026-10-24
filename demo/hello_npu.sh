#!/usr/bin/env bash
# hello_npu.sh — minimal end-to-end demo: is the NPU alive and can it talk?
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "==> board:    $(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null || unknown)"
echo "==> soc_id:   $(cat /sys/devices/soc0/soc_id 2>/dev/null || unknown)  (460 = faked for QNN, real value is 449)"
echo "==> cdsp:     $(cat /sys/class/remoteproc/remoteproc*/name 2>/dev/null | tr '\n' ' ')"
echo
echo "==> running Qwen2.5-0.5B on the Hexagon NPU:"
bash "$SCRIPT_DIR/scripts/run.sh" qwen05 '用一句话介绍你自己'
