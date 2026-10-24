#!/usr/bin/env bash
# lib_models.sh — model registry shared by run.sh / chat.sh / bench.sh.
# Do not execute directly.

MODELS_ROOT="${MODELS_ROOT:-$HOME/dragon-q8b-npu-models}"

# model_dir <name>      -> bundle directory
# model_config <name>   -> genie config json inside the bundle
# model_template <name> -> chatml | llama3
model_dir() {
    case "$1" in
        qwen05)     echo "$MODELS_ROOT/qwen05" ;;
        llama1b)    echo "$MODELS_ROOT/llama1b" ;;
        llama1b-1k) echo "$MODELS_ROOT/llama1b-1k" ;;
        *) echo "unknown model: $1 (expected qwen05 | llama1b | llama1b-1k)" >&2; return 1 ;;
    esac
}

model_config() {
    case "$1" in
        qwen05)     echo "qwen2.5-0.5B-1k-htp.json" ;;
        llama1b)    echo "htp-model-config-llama32-1b-gqa.json" ;;
        llama1b-1k) echo "htp-model-config-llama32-1b-gqa.json" ;;
    esac
}

model_template() {
    case "$1" in
        qwen05)     echo "chatml" ;;
        llama1b)    echo "llama3" ;;
        llama1b-1k) echo "llama3" ;;
    esac
}

format_prompt() {
    local name="$1" user_text="$2"
    local sys="You are a helpful assistant."
    case "$(model_template "$name")" in
        chatml)
            printf '<|im_start|>system\n%s<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n' "$sys" "$user_text"
            ;;
        llama3)
            printf '<|start_header_id|>system<|end_header_id|>\n\n%s<|eot_id|><|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\n%s<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n' "$sys" "$user_text"
            ;;
    esac
}

list_models() {
    echo "available models: qwen05 (Qwen2.5-0.5B, Chinese) | llama1b (Llama3.2-1B, 4k ctx) | llama1b-1k (Llama3.2-1B, 1k ctx)"
}
