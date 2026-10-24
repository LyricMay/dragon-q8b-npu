# Troubleshooting

Errors are ordered by where they appear in the bring-up flow.

## 1. Kernel / device nodes

**`/dev/fastrpc-cdsp` missing**
```bash
sudo modprobe fastrpc          # load the module
ls /dev/fastrpc-*              # should list fastrpc-cdsp (+ variants)
dmesg | tail                   # look for fastrpc errors
```
If `modprobe` fails, the kernel has no FastRPC support — use Armbian's vendor
kernel for Dragon Q8B (7.0.11-vendor-sc8280xp).

**CDSP remoteproc not running**
```bash
cat /sys/class/remoteproc/remoteproc*/state
dmesg | grep -iE "cdsp|remoteproc"
```
Usually fixed by rebooting (firmware load race). Persistent failures mean the
firmware file is missing: `/lib/firmware/qcom/sc8280xp/qccdsp8280.mbn` must
exist (Armbian's `armbian-firmware-full` provides it).

## 2. soc_id / backend init

**`[ERROR] "Could not initialize backend due to error = 4000"`**
The QNN HTP backend refuses to start because `/sys/devices/soc0/soc_id` reads
the real `449`. Fix (persists across reboots once `fastrpc.service` is enabled):
```bash
sudo /usr/libexec/fastrpc/setup-dsp.sh
cat /sys/devices/soc0/soc_id   # must print 460
```

**`Failed to create device: 14001`** (QAIRT 2.37-era tools such as
`qnn-net-run`, `genie-t2t-run` from the QAIRT SDK)
Auto-architecture detection fails on SC8280XP. Export
`QNN_HTP_ARCH_VERSION=68`. The Radxa model bundles in this repo do **not**
need this — their `htp_backend_ext_config.json` pins `dsp_arch: v68`.

## 3. Model loading

**`Could not create context from binary for context index = 0 : err 5005`**
(`QNN_CONTEXT_ERROR_CREATE_FROM_BINARY`)
The context binary was compiled for a different Hexagon architecture:
```bash
strings models/*.bin | grep -o "soc_type=[A-Z0-9]*" | head
strings models/*.bin | grep -o "min_arch=[0-9]*" | head
```
`soc_type=SC8380XP` / `min_arch=73` (X Elite / 8-Gen-3-class) will never run on
this v68 NPU. Download a v68 build via `scripts/install-model.sh`.

**Download truncated / corrupted**
`install-model.sh` resumes partial downloads (`curl -C -`). Verify the file
size matches the ModelScope listing; re-run the script if in doubt.

## 4. Runtime

**Runs, but output is garbage / instant EOS**
Prompt template mismatch — each model needs its own chat template (ChatML for
Qwen, Llama-3 for Llama). `scripts/run.sh` handles this; if you call
`genie-t2t-run` directly, build the prompt accordingly.

**Very slow generation**
- First run per boot pays one-time costs (page cache warm-up, DSP session).
  Run `scripts/bench.sh` which warms up before measuring.
- `poll: true` in the genie config keeps a CPU core spinning for low latency;
  set it to `false` to trade latency for CPU usage.

**`cannot open shared object file libcdsprpc.so.1`**
FastRPC userspace not installed: `sudo bash setup.sh` (installs the bundled
debs). The lib must be in `/usr/lib/aarch64-linux-gnu/`.

## 5. Getting more help

Include the output of `demo/hello_npu.sh` and
`dmesg | grep -iE "fastrpc|cdsp" | tail -30` in your issue.
