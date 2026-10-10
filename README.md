# llm-bench
Misc local LLM benchmarking

Performance figures (llama-bench tokens/s) from `~/models/*.md` on the two lab hosts. All numbers fully GPU-offloaded; pp512/tg128 at low context depth unless noted.

## Hosts

### strix — workstation (GMKtec NucBox EVO-X2)

| Component | Value |
|---|---|
| Chassis | GMKtec NucBox EVO-X2, Sixunited AXB35-02 motherboard |
| CPU | AMD Ryzen AI MAX+ 395, 16C/32T, max 3.0 GHz |
| GPU | AMD Radeon 8060S (RDNA4, gfx1151, RADV STRIX_HALO), iGPU UMA |
| Memory | 62 GiB OS-visible + 64 GiB GPU reservation (~128 GiB UMA total) |
| Fans | 2x CPU fans (fan3 unused, reads 0 RPM) — controlled by embedded controller (EC), no Linux PWM interface |
| OS | Fedora 44 KDE, kernel 7.2.8-200.fc44.x86_64 |
| Vulkan | API 1.4.354, Mesa RADV 26.2.3 |
| llama.cpp | 0.6.0-dev build 11548 (781dbc5ac), Vulkan, `~/bin/llama-server` |

#### Fan control & power management (source: the workstation's `~/dev/strix_fedora/`, vendored in [`strix-halo/`](strix-halo/))

The EC owns the fan curve and the APU power limits; the stock setup idled loud (Tctl 62°C, GPU 39W, fans ~1500 RPM). Fixed with the `ec_su_axb35` kernel module (cmetz/ec-su_axb35-linux, DKMS auto-rebuild on kernel updates) + `ec-fancontrol.service`, which applies on every boot:

- **Power mode `quiet`** (STAPM 54W / fast PPT 100W / slow 54W). Alternatives: `balanced` 85W, `performance` 120W — switchable via `power-quiet|balanced|performance` aliases.
- **Custom fan curves** — ramp-up `70,80,88,95,97` °C, ramp-down `60,65,85,93,96` °C (hysteresis vs hunting); curve mode on fan1/fan2.

Measured effect: Tctl 62→55°C (30°C idle at 2026-10 check), GPU PPT 39→26W, fans 1500→~1050 RPM (EC hardware floor — fans never fully stop). **The box is silent at this setup.**

Throughput impact (Ollama, qwen3:120b Vulkan): quiet 27.9 t/s vs balanced 29.5 t/s eval — **+5.9% for +56% power**. UMA workloads are bandwidth-bound, not compute-bound, so `quiet` is the default for LLM benchmarking; sustained clocks, not PPT, are what limits tg. `power_mode` is writable per-run at `/sys/class/ec_su_axb35/apu/power_mode` if a benchmark wants to A/B power levels.

### titan — server (TITAN RTX node)

| Component | Value |
|---|---|
| CPU | AMD Ryzen 7 5800X3D, 8C/16T |
| GPU | NVIDIA TITAN RTX, 24 GB (24,030 MiB usable), compute capability 7.5 |
| OS / driver | NVIDIA driver 610.57.04 (advertises CUDA 13.3) |
| llama.cpp | b10443 (27df9199d), CUDA arch 75, `GGML_CUDA_FA=ON`, `GGML_CUDA_GRAPHS=ON` |

## Strix results (Vulkan, UMA)

| Model | Quant | Size | pp512 | tg128 | Notes |
|---|---|---:|---:|---:|---|
| Qwen3.5-35B-A3B (34.7B / 3B active) | UD-Q4_K_XL | 18.3 GiB | 850.7 | 50.7 | fastest 35B tg |
| | IQ4_XS | 17.4 GiB | 767.8 | 49.9 | |
| | UD-MXFP4_MOE | 18.2 GiB | 845.7 | 40.8 | -20% tg vs Q4_K_XL |
| | UD-Q8_K_XL | 39.1 GiB | 664.6 | 29.3 | 2x size, half speed |
| Qwen3.5-122B-A10B | UD-Q4_K_XL | 63.7 GiB | 229.4 | 21.5 | |
| | MXFP4_MOE | 63.6 GiB | 228.7 | 16.8 | |
| GPT-OSS-120B | MXFP4 | 59.0 GiB | 475.5 | 47.7 | ~35B speed at 120B |
| Qwen3.8-27B (hybrid SSM) | Q4_K_M | 15.9 GiB | 266-290 | 11.7 | flags make no difference; bandwidth-bound |
| | + MTP draft 1 | | | 19.5 | 1.65x |
| | + **MTP draft 3** | | | **27.1** | **2.30x**, 69-82% acceptance; draft 5/7 = 25.0 / 23.5 |
| Nemotron-3.5 Lightning 30B-A3B | UD-Q4_K_M | 23.5 GiB | 1173 | 54.8 | t4 |
| Gemma-4 26B-A4B | UD-IQ4_XS | 12.5 GiB | 1255.8 | 51.3 | |
| | UD-Q4_K_M | 16.9 GiB | 1237.8 | 48.2 | |

Depth effects (Qwen3.8-27B @ 8K context depth): pp2048 217-232, tg64 11.0-11.6; FA on +4.3% tg; Q8 KV ~neutral perf.

Serving (Gemma-4 26B-A4B IQ4_XS, chat endpoint incl. prompt + HTTP overhead): 43.5 t/s single, 101-106 t/s aggregate at 4 concurrent. vLLM ROCm BF16 graphs on the same box: 24.2 single, ~50 at 4 concurrent (quant-vs-BF16 deployment comparison, not engine-isolated).

llama.cpp builds by batch: Qwen3.5/GPT-OSS b8146 (2026-02-28); Qwen3.8-27B b10218 + 9723942 (2026-08-30); Qwen3.8-27B / Gemma-4 b10826 73a43d1f (2026-09-10). Current installed: b11548.

## Titan results (CUDA, CC 7.5)

| Model | Quant | pp512 | tg128 | Notes |
|---|---|---:|---:|---|
| Qwen3.8-27B | Q4_K_M | 778.8 (t8) | 30.3 | @8K depth: pp2048 712.6, tg64 29.5 |
| | UD-Q4_K_XL | 785-807 | 28.6 | faster pp, slower tg |
| | + **MTP draft 2** | | **49.7** | +61%; 92% accept code / 56% prose; draft 5/7 degrade |
| Nemotron-3.5 Lightning 30B-A3B | UD-Q4_K_M | 2422 | 132.7 | t16 |
| Qwen3.6-35B-A3B | UD-Q4_K_M | 2140 | 115.3 | full offload, 20.6 GiB |
| Gemma-4 26B-A4B | UD-IQ4_XS | 2674 | 96.6 | 89.8 @ 8K depth |
| gpt-oss-20b | — | — | 142 | from ranking table only |

Threads/ubatch flat on both hosts for these models (t1-t32 measured). FA helps pp on CUDA (+17.6% at 8K depth) but is near-neutral on Vulkan at shallow context.

## Cross-host insights

- Strix tg ceiling is UMA bandwidth: tg ~ bandwidth / weight-GiB at ~73% efficiency — smaller quant = proportionally faster tg.
- pp is 23-25x cheaper per token than tg on both hosts (SSM hybrid makes long prompts cheap).
- MTP is the only large tg lever measured: 2.30x on strix (draft 3), +61% on titan (draft 2); optimal draft size differs by hardware and prompt type.
- KV q8_0 ~neutral perf; only worthwhile at 32k+ context (halves KV memory).

## TODO

- [ ] Add `orchestrator.py` + `prompt.md`: deterministic-domain benchmark with deliberately planted flaws. Goal: see which models trip up on the flaws (if any) and gauge general output quality. Model-agnostic (same harness across strix + titan lineups), deterministic grading where possible.
- [ ] Reformat both hosts onto the same base OS (titan is Arch, ws is Fedora Workstation) so runtime/driver versions are comparable across benchmark runs.
- [ ] Context-length sweep: run pp and tg at increasing ctx depths (e.g. 4k/8k/16k/32k/64k), chart the pp:tg ratio vs ctx to find where each model/host drops off and how steeply.
- [ ] Flag optimization per model for highest throughput: sweep threads/ubatch/FA/KV-type/spec-draft per model per host, lock in a tuned profile.

## Known gaps for future benchmarks

- End-to-end request latency under concurrency (existing serving numbers are 1 and 4 concurrent only).
- MTP at long/occupied context.
- Long-prompt pp decay curves.
- Equal-precision engine comparisons (Vulkan quantized vs vLLM ROCm BF16 conflates precision and engine).
