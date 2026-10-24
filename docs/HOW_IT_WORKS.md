# How it works

This document explains the full software path a prompt travels on the Radxa
Dragon Q8B, and why each component exists.

## Hardware

| block | part |
|---|---|
| SoC | Qualcomm SC8280XP (Snapdragon 8cx Gen 3) |
| NPU | Hexagon QDSP6 v68, 29+ TOPS, 3 SC (compute subsystem) on the CDSP |
| DSP partitions | ADSP (audio), CDSP (compute — this is what we use), SDSP (sensors) |

## Boot-time chain

1. **CDSP firmware** — `/lib/firmware/qcom/sc8280xp/qccdsp8280.mbn`, shipped by
   Armbian's firmware package. The `cdsp` remoteproc loads it and the DSP boots
   at system boot (check `cat /sys/class/remoteproc/*/state` → `running`).
2. **fastrpc kernel module** — part of the vendor kernel. When a process opens
   `/dev/fastrpc-cdsp` a FastRPC session can be created.
3. **`fastrpc.service`** (bundled deb, enabled by `setup.sh`) runs
   `/usr/libexec/fastrpc/setup-dsp.sh` at every boot:
   - creates `/usr/lib/dsp` → `/usr/share/qcom/sc8280xp/radxa/dragon-q8b/dsp`;
   - bind-mounts `/tmp/fake-soc0/soc_id` (containing `460`) over
     `/sys/devices/soc0/soc_id`. **This fake is mandatory** — with the real
     value 449 the QNN HTP backend fails with error `4000`.
4. **`cdsprpcd.service`** — udev starts this daemon when `/dev/fastrpc-cdsp`
   appears; it handles RPC bookkeeping on the CPU side.

## Inference chain (genie-t2t-run)

```
genie-t2t-run ── libGenie.so ── libQnnHtp.so ── libQnnHtpV68Stub.so
     │                                              │  libcdsprpc.so (FastRPC)
     │                                              ▼
     │                                       /dev/fastrpc-cdsp
     │                                              │
     ▼                                              ▼
tokenizer.json                          libQnnHtpV68Skel.so (loaded on CDSP)
models/*.serialized.bin ──────────────►  QNN context binary → executes on Hexagon
```

- The **context binary** (`models/*.serialized.bin`) contains the pre-compiled,
  quantized (w4a16) compute graph for the model. It is architecture-specific:
  v68 binaries only run on v68. `strings models/xxx.bin | grep soc_type` shows
  what it was built for.
- `ADSP_LIBRARY_PATH=<bundle-dir>` tells the stub where to find
  `libQnnHtpV68Skel.so` (the DSP-side runtime). That's the only env needed —
  the bundled 2.40.1 runtime pins `dsp_arch: v68` in its
  `htp_backend_ext_config.json`.
- Sampling/tokenization/detokenization run on the CPU; the transformer
  forward pass runs on the NPU.

## Why the .debs are extract-only for firmware

`radxa-firmware-sc8280xp` ships both the DSP *shells* (`/usr/share/qcom/...`)
and CDSP/ADSP *boot firmware* (`/lib/firmware/qcom/sc8280xp/...`). Armbian
already provides the boot firmware through `armbian-firmware-full`, so
installing the package directly would make dpkg fail with a file-overwrite
conflict. `setup.sh` therefore extracts the `.deb` and copies only
`/usr/share/qcom/sc8280xp` — the pieces Armbian lacks.

## Model sources (ModelScope, radxa organization)

| repo | notes |
|---|---|
| `radxa/Qwen2.5-0.5B-v68` | w4a16, 1k ctx, ChatML template |
| `radxa/Llama3.2-1B-4096-qairt-v68` | w4a16, 4k ctx, llama3 template |
| `radxa/Llama3.2-1B-1024-qairt-v68` | w4a16, 1k ctx |

Measured with the Genie profile on this board: Qwen2.5-0.5B — 24.3 tokens/s
generation, 309 tokens/s prompt processing, ~0.9 s init.
