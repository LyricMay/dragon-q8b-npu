#!/usr/bin/env bash
# run.sh — single-shot NPU inference.
#
# Usage: bash scripts/run.sh <model> <prompt>
#        bash scripts/run.sh qwen05 '你好，介绍一下你自己'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_ROOT="${MODELS_DIR:-$HOME/dragon-q8b-npu-models}"

# shellcheck source=scripts/lib_models.sh
source "$SCRIPT_DIR/lib_models.sh"

NAME="${1:-}"
PROMPT="${2:-}"
[[ -n "$NAME" ]] || { echo "usage: bash scripts/run.sh <model> <prompt>"; list_models; exit 1; }
[[ -n "$PROMPT" ]] || { echo "error: empty prompt"; exit 1; }

DIR="$(model_dir "$NAME")"
CONFIG="$(model_config "$NAME")"
PROMPT_TEXT="$(format_prompt "$NAME" "$PROMPT")"

export LD_LIBRARY_PATH="$DIR:/usr/lib/aarch64-linux-gnu"
export ADSP_LIBRARY_PATH="$DIR"

# genie resolves the config, tokenizer and ctx-bins relative to the CWD
cd "$DIR"
OUT="$(./genie-t2t-run -c "$CONFIG" -p "$PROMPT_TEXT" 2>/dev/null | sed -n '/^\[BEGIN\]/,/\[END\]/p')"
STATUS=$?
# strip the [BEGIN]/[END] markers and blank padding lines
printf '%s' "$OUT" \
    | sed -e 's/^\[BEGIN\]: \{0,1\}//' -e 's/\[END\].*$//' -e '/./,$!d'
exit $STATUS
