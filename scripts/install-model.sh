#!/usr/bin/env bash
# install-model.sh — download a pre-built Hexagon v68 model bundle from ModelScope.
#
# Usage: bash scripts/install-model.sh [qwen05|llama1b|llama1b-1k] [target_dir]
set -euo pipefail

log()  { printf '\033[1;36m[install-model]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[install-model] error:\033[0m %s\n' "$*" >&2; exit 1; }

readonly DEFAULT_ROOT="${MODELS_DIR:-$HOME/dragon-q8b-npu-models}"

# name | modelscope repo | config json | prompt template | description
MODELS=(
  "qwen05|radxa/Qwen2.5-0.5B-v68|qwen2.5-0.5B-1k-htp.json|chatml|Qwen2.5-0.5B-Instruct, Chinese, 1k ctx (~640 MB)"
  "llama1b|radxa/Llama3.2-1B-4096-qairt-v68|htp-model-config-llama32-1b-gqa.json|llama3|Llama3.2-1B-Instruct, English, 4k ctx (~1.8 GB)"
  "llama1b-1k|radxa/Llama3.2-1B-1024-qairt-v68|htp-model-config-llama32-1b-gqa.json|llama3|Llama3.2-1B-Instruct, English, 1k ctx (~1.8 GB)"
)

usage() {
    echo "Available models:"
    for m in "${MODELS[@]}"; do IFS='|' read -r name repo cfg tpl desc <<<"$m"; echo "  $name  —  $desc"; done
}

NAME="${1:-}"
[[ -n "$NAME" ]] || { usage; exit 1; }

MODEL_INFO=""
for m in "${MODELS[@]}"; do
    if [[ "$m" == "$NAME|"* ]]; then MODEL_INFO="$m"; break; fi
done
[[ -n "$MODEL_INFO" ]] || { echo "unknown model '$NAME'"; usage; exit 1; }

IFS='|' read -r NAME REPO CONFIG TEMPLATE DESC <<<"$MODEL_INFO"
DEST="${2:-$DEFAULT_ROOT/$NAME}"

log "model:  $DESC"
log "source: https://modelscope.cn/models/$REPO"
log "target: $DEST"
mkdir -p "$DEST"

BASE="https://modelscope.cn/models/$REPO/resolve/master"

# shared runtime files
RUNTIME_FILES=(genie-t2t-run libGenie.so libQnnHtp.so libQnnHtpNetRunExtensions.so \
               libQnnHtpV68Skel.so libQnnHtpV68Stub.so libQnnSystem.so tokenizer.json)
for f in "${RUNTIME_FILES[@]}"; do
    [[ -s "$DEST/$f" ]] && { log "have  $f"; continue; }
    log "fetch $f"
    curl -fsSL --retry 3 -o "$DEST/$f" "$BASE/$f" || die "download failed: $f"
done
chmod +x "$DEST/genie-t2t-run"

# bundle-specific config + context binaries
mapfile -t CTX_BINS < <(curl -fsSL "$BASE/$CONFIG" | python3 -c "import json,sys;print('\n'.join(json.load(sys.stdin)['dialog']['engine']['model']['binary']['ctx-bins']))")
log "config: $CONFIG  context bins: ${CTX_BINS[*]}"
curl -fsSL --retry 3 -o "$DEST/$CONFIG" "$BASE/$CONFIG" || die "download failed: $CONFIG"
curl -fsSL --retry 3 -o "$DEST/htp_backend_ext_config.json" "$BASE/htp_backend_ext_config.json" || die "download failed: htp_backend_ext_config.json"
mkdir -p "$DEST/$(dirname "${CTX_BINS[0]}")"
for b in "${CTX_BINS[@]}"; do
    [[ -s "$DEST/$b" ]] && { log "have  $b ($(du -h "$DEST/$b" | cut -f1))"; continue; }
    log "fetch $b (large, please wait)"
    curl -fSL --retry 3 -C - -o "$DEST/$b" "$BASE/$b" || die "download failed: $b"
done

echo
log "done. run it:"
echo "    bash scripts/run.sh $NAME '你好，用一句话介绍你自己'"
