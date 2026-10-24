#!/usr/bin/env bash
# chat.sh — simple multi-turn chat on the NPU.
#
# Each turn is a fresh genie-t2t-run invocation with the full conversation in
# the prompt (the NPU context is not persisted between processes). The 1k/4k
# context window of the compiled model is the hard limit.
#
# Usage: bash scripts/chat.sh [qwen05|llama1b|llama1b-1k]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib_models.sh
source "$SCRIPT_DIR/lib_models.sh"

NAME="${1:-qwen05}"
DIR="$(model_dir "$NAME")"
CONFIG="$(model_config "$NAME")"
TEMPLATE="$(model_template "$NAME")"
SYS="You are a helpful assistant. Keep answers concise."

HISTORY=()
TURN=0

build_prompt() {
    local sys="$1" ; shift
    local out=""
    case "$TEMPLATE" in
        chatml)
            out="<|im_start|>system\n${sys}<|im_end|>\n"
            local h
            for h in "${HISTORY[@]}"; do
                local role="${h%%::*}" text="${h#*::}"
                out+="<|im_start|>${role}\n${text}<|im_end|>\n"
            done
            out+="<|im_start|>user\n__TURN__<|im_end|>\n<|im_start|>assistant\n"
            ;;
        llama3)
            out="<|start_header_id|>system<|end_header_id|>\n\n${sys}<|eot_id|>"
            local h
            for h in "${HISTORY[@]}"; do
                local role="${h%%::*}" text="${h#*::}"
                case "$role" in
                    user)  out+="<|start_header_id|>user<|end_header_id|>\n\n${text}<|eot_id|>" ;;
                    assistant) out+="<|start_header_id|>assistant<|end_header_id|>\n\n${text}<|eot_id|>" ;;
                esac
            done
            out+="<|start_header_id|>user<|end_header_id|>\n\n__TURN__<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            ;;
    esac
    printf '%b' "$out"
}

extract_answer() {
    # take everything between [BEGIN]: and [END], trim markers + blank padding
    sed -n '/^\[BEGIN\]/,/\[END\]/p' \
        | sed -e 's/^\[BEGIN\]: \{0,1\}//' -e 's/\[END\].*$//' -e '/./,$!d'
}

echo "NPU chat ($NAME) — type 'exit' to quit, 'new' to reset history"
while true; do
    if (( TURN == 0 )); then
        printf '\033[1;35myou>\033[0m '
    else
        printf '\033[1;35myou>\033[0m '
    fi
    IFS= read -r USER_INPUT || break
    case "$USER_INPUT" in
        exit|quit) break ;;
        new) HISTORY=(); TURN=0; echo "(history cleared)"; continue ;;
        "") continue ;;
    esac

    PROMPT="$(build_prompt "$SYS")"
    PROMPT="${PROMPT/__TURN__/$USER_INPUT}"

    export LD_LIBRARY_PATH="$DIR:/usr/lib/aarch64-linux-gnu"
    export ADSP_LIBRARY_PATH="$DIR"

    REPLY="$(cd "$DIR" && ./genie-t2t-run -c "$CONFIG" -p "$PROMPT" 2>/dev/null | extract_answer)"
    REPLY="${REPLY//$'\n'[[:space:]]*/$'\n'}"
    REPLY="${REPLY# }"

    if [[ -z "$REPLY" ]]; then
        printf '\033[1;33m(no output — context window may be full; type %snew%s to reset history)\033[0m\n' "'" "'"
        continue
    fi
    printf '\033[1;32massistant>\033[0m %s\n' "$REPLY"
    HISTORY+=("user::$(printf '%s' "$USER_INPUT" | tr '\n' ' ')")
    HISTORY+=("assistant::$(printf '%s' "$REPLY" | tr '\n' ' ')")
    TURN=$((TURN + 1))
done
