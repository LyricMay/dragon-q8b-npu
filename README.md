# dragon-q8b-npu

Run large language models on the **Hexagon v68 NPU** of the **Radxa Dragon Q8B**
(Qualcomm SC8280XP / Snapdragon 8cx Gen 3) — on a **fresh Armbian**, with one
command and no external apt repository.

Tested on: Armbian 26.8.1 (vendor kernel 7.0.11-vendor-sc8280xp), Radxa Dragon Q8B.

```
$ sudo bash setup.sh
$ bash scripts/install-model.sh qwen05
$ bash scripts/run.sh qwen05 '你好，用一句话介绍你自己'
[BEGIN]: 我叫AI助手，能够提供信息和帮助您。[END]
```

**在全新 Armbian 上，克隆本仓库后三步即可跑通 NPU 推理**(中文说明见下)。

## Models

All models are compiled for **Hexagon v68** and published by Radxa on ModelScope.
Binaries compiled for other chips (v69/v73/v75/v79 — e.g. Snapdragon 8 Gen 1/2/3,
X Elite) **cannot** run on this NPU; you will get QNN error `5005`.

| model id | model | language | context | size | speed (measured) |
|---|---|---|---|---|---|
| `qwen05` | Qwen2.5-0.5B-Instruct | 中/EN | 1k | ~640 MB | 24.3 tok/s gen, 309 tok/s prompt |
| `llama1b` | Llama-3.2-1B-Instruct | EN | 4k | ~1.8 GB | ~20–25 tok/s gen |
| `llama1b-1k` | Llama-3.2-1B-Instruct | EN | 1k | ~1.8 GB | ~20–25 tok/s gen |

## Quick start

Requirements: Radxa Dragon Q8B, Armbian (Ubuntu-based, aarch64), root.

```bash
git clone <this-repo> dragon-q8b-npu
cd dragon-q8b-npu

sudo bash setup.sh                        # system: FastRPC + DSP env (debs are bundled)
bash scripts/install-model.sh qwen05      # download model (~640 MB from ModelScope)
bash scripts/run.sh qwen05 '你好'          # single prompt
bash scripts/chat.sh qwen05               # multi-turn chat (type exit to quit)
bash scripts/bench.sh qwen05              # rough throughput
```

`setup.sh` does, in order:

1. load the `fastrpc` kernel module (already in Armbian's vendor kernel);
2. `dpkg -i` the bundled `.deb` files in `debs/` — Qualcomm FastRPC userspace
   (`fastrpc`, `libcdsprpc1`, …, version 1.0.7-3) taken from Radxa's official
   repo, so **no network apt access is needed**;
3. extract only the DSP shells (`fastrpc_shell_3`, …) from
   `radxa-firmware-sc8280xp` into `/usr/share/qcom` — extract-only, because
   Armbian already ships the CDSP boot firmware and the package would collide
   with it;
4. run `/usr/libexec/fastrpc/setup-dsp.sh` (ships in the deb): creates
   `/usr/lib/dsp` and **bind-mounts a fake soc_id 449→460** — QNN's HTP backend
   refuses to initialize with the real 449 (error `4000`); this also runs at
   every boot via the enabled `fastrpc.service`;
5. verify CDSP remoteproc / device nodes / soc_id.

## 中文说明

在全新 Armbian(苏梅 Armbian 26.8.x 皆可)上：

```bash
git clone <本仓库> dragon-q8b-npu
cd dragon-q8b-npu

sudo bash setup.sh                    # 安装系统组件(deb 包已内置,无需外部 apt 源)
bash scripts/install-model.sh qwen05  # 下载 Qwen2.5-0.5B(约 640MB,来自 ModelScope)
bash scripts/run.sh qwen05 '你好，介绍一下你自己'
```

- `qwen05` 中文对话效果最好;`llama1b` 是最大的 v68 模型(英文)。
- 多轮对话:`bash scripts/chat.sh qwen05`(注意：每轮重新加载模型、重新编码历史，上下文上限 1k)。
- 模型保存在 `~/dragon-q8b-npu-models/`(可用 `MODELS_DIR=...` 自定义)。
- DeepSeek / 3B 以上模型：目前 **没有** v68 编译版本(ModelScope 上 radxa 的
  DeepSeek 只有 RKLLM/TPU/v73 版)。用错架构的二进制会报 QNN 错误 `5005`。

## Troubleshooting

| symptom | cause / fix |
|---|---|
| `error = 4000` / `initializeBackend FAILED` | soc_id is not faked to 460. Run `sudo /usr/libexec/fastrpc/setup-dsp.sh` (also runs at boot via `fastrpc.service`). |
| `Failed to create device: 14001` (QAIRT 2.37 tools) | auto-detection fails on SC8280XP; set `QNN_HTP_ARCH_VERSION=68`. Bundled Radxa models don't need this (their config pins `dsp_arch: v68`). |
| `Could not create context from binary … err 5005` | the context binary was compiled for another Hexagon version (check `strings model.bin \| grep soc_type`). You need a v68 build. |
| `/dev/fastrpc-cdsp missing` | `sudo modprobe fastrpc`; if the node still doesn't appear, the kernel lacks FastRPC. |
| CDSP remoteproc not running after boot | firmware loading issue — check `dmesg \| grep -i cdsp`; a reboot usually fixes it. |

More details: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md),
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Repository layout

```
setup.sh                  one-command bootstrap (fresh Armbian → NPU ready)
debs/                     bundled FastRPC userspace .debs (offline install)
scripts/install-model.sh  download v68 model bundles from ModelScope
scripts/run.sh            single-shot inference
scripts/chat.sh           multi-turn chat loop
scripts/bench.sh          rough throughput estimate
scripts/lib_models.sh     model registry (dir/config/prompt template)
demo/hello_npu.sh         end-to-end sanity demo
docs/                     background, internals, troubleshooting
```

## Acknowledgements & licensing

- FastRPC userspace debs: from [Radxa](https://radxa.com)'s official apt repo
  (`radxa-repo.github.io`), based on Qualcomm's FastRPC (see `debs` copyright files).
- Model bundles: [radxa on ModelScope](https://modelscope.cn/organization/radxa)
  (Qwen2.5 © Alibaba under Apache-2.0 / Qwen license; Llama 3.2 © Meta under the
  Llama 3.2 Community License).
- Scripts in this repository: MIT (see [LICENSE](LICENSE)).

This is an unofficial community project, not affiliated with Radxa or Qualcomm.
