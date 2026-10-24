#!/usr/bin/env bash
# bench.sh — quick throughput estimate (wall-clock based).
#
# Usage: bash scripts/bench.sh [model] [rounds]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib_models.sh
source "$SCRIPT_DIR/lib_models.sh"

NAME="${1:-qwen05}"
ROUNDS="${2:-3}"
DIR="$(model_dir "$NAME")" || exit 1
CONFIG="$(model_config "$NAME")"

# a task with a bounded answer length — long open-ended prompts can loop until
# the compiled context window (1k on qwen05) is exhausted
case "$(model_template "$NAME")" in
    chatml)  PROMPT=$(printf '<|im_start|>user\nCount from 1 to 60, separated by commas.<|im_end|>\n<|im_start|>assistant\n') ;;
    llama3)  PROMPT=$(printf '<|start_header_id|>user<|end_header_id|>\n\nCount from 1 to 60, separated by commas.<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n') ;;
esac

export LD_LIBRARY_PATH="$DIR:/usr/lib/aarch64-linux-gnu"
export ADSP_LIBRARY_PATH="$DIR"

echo "warming up (model load, page cache)..."
(cd "$DIR" && ./genie-t2t-run -c "$CONFIG" -p "$PROMPT") >/dev/null 2>&1

TOTAL=0
OK=0
for i in $(seq 1 "$ROUNDS"); do
    START=$(date +%s.%N)
    OUT="$( (cd "$DIR" && ./genie-t2t-run -c "$CONFIG" -p "$PROMPT") 2>/dev/null | sed -n '/^\[BEGIN\]/,/\[END\]/p' )"
    END=$(date +%s.%N)
    if [[ -z "$OUT" ]]; then
        echo "round $i: model returned nothing (context exceeded?) — skipped"
        continue
    fi
    ELAPSED=$(awk -v a="$START" -v b="$END" 'BEGIN{printf "%.2f", b-a}')
    WORDS=$(printf '%s' "$OUT" | wc -w)
    WPS=$(awk -v t="$WORDS" -v e="$ELAPSED" 'BEGIN{if(e>0) printf "%.1f", t/e}')
    echo "round $i: ~$WORDS words in ${ELAPSED}s (~${WPS} words/s)"
    TOTAL=$(awk -v a="$TOTAL" -v e="$ELAPSED" 'BEGIN{printf "%.2f", a+e}')
    OK=$((OK + 1))
done

if (( OK > 0 )); then
    AVG=$(awk -v t="$TOTAL" -v n="$OK" 'BEGIN{printf "%.2f", t/n}')
    echo "average wall-clock: ${AVG}s per round"
fi
echo
echo "note: rough wall-clock estimate. Reference on Dragon Q8B (Genie profile):"
echo "  Qwen2.5-0.5B : 24.3 tokens/s generation, 309 tokens/s prompt processing"
echo "  Llama3.2-1B  : roughly 20-25 tokens/s generation"
