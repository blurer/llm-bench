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
| GPU cooling | **Modded**: Morpheus II air cooler + 2x Noctua slim 120mm fans (stock blower removed) |
| RAM | 62 GB |
| Models | `/mnt/data/models/` |
| OS | Arch Linux, kernel 7.2.9-arch1-1 |
| Driver | NVIDIA 615.78.08 |
| llama.cpp | 0.5.0-dev build 11222 (a97cce86a), CUDA arch 75, `/usr/local/bin/llama-server` |

#### GPU fan control (scripts vendored in [`titan-cooling/`](titan-cooling/))

The stock blower is gone; the GPU intake fan and the NR200 case-exhaust fan run off motherboard PWM headers (the driver reports the GPU as fanless). Two enabled services manage them:

- `fan-control.service` — pins **75%** at boot (`fan-control.sh 75`)
- `fan-control-auto.service` — daemon (3s interval, 5°C hysteresis) stepping 50/75/100% at GPU 60/70/80°C, auto below 45°C (same ladder for CPU/chipset/board sensors)

Effect on benchmarking: sustained LLM inference holds 75%+ with stable thermals/clocks between runs; below the 45°C floor the box is effectively silent. Manual override: `sudo fan-control.sh {25|50|75|100}`.

Results below were measured on the earlier install (driver 610.57.04, llama.cpp b10443 / 27df9199d, `GGML_CUDA_FA=ON`, `GGML_CUDA_GRAPHS=ON`). Re-baselined 2026-10-10 on the updated stack (driver 615.78.08, llama.cpp b11222) with identical methodology — Qwen3.8-27B Q4_K_M pp512 768.2 / tg128 30.2, pp2048@8K 711.2 / tg64@8K 29.2: no material delta, numbers stand.

Methodology notes for reproducing: fully GPU-offload (`-ngl 99`), FA on, verify the GPU is actually idle first (`nvidia-smi --query-gpu=memory.used --format=csv,noheader`) — a resident llama-server silently halves results.

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
| LFM2.5-24B-A2B (lfm2moe) | UD-Q4_K_XL | 13.9 GiB | 2216.9 | 100.2 | 2026-10-14; t8/ub2048. q8_0 KV: pp 2255.5, tg 98.8 (~neutral). @8K depth: pp2048 1652.4, tg64 89.2. Fastest pp+tg on strix; no MTP (no GGUF head exists; only vLLM/NVFP4 eagle3 for 8B variant) |
| Qwen3.6-35B-A3B | UD-Q4_K_M-MTP @65k q8_0 | 21.1 GiB | — | 57.4 | 2026-10-14, baseline (no spec), rsync'd from titan |
| | + **MTP draft 3** | | | **81.9** | +43%; code 88.6 / prose 75.2; draft 2 = 80.1; 1.7x gpt-oss-120b |
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
| | UD-Q4_K_XL @65k q8_0 KV | 743.7 | 28.2 | 2026-10-14: c65536, q8_0 both, b/ub 2048, t8; 19.5 GiB |
| | + **MTP draft 2** | | **49.0** | +74%; 20.8 GiB; draft 1/3 = 43.4/48.2; code 54.1, prose 44.0 |

The older `+ MTP draft 2 49.7` row is the **uncensored Q4_K_M** GGUF (see its notes doc); the 2026-10-14 `@65k` rows are the plain unsloth UD-Q4_K_XL. llama-bench has no spec support in the b11222 build, so MTP figures come from the server-request method (coding + DNS prompts ×2, 128 tokens, temp 0 seed 42, ignore EOS, no prompt cache; mean per-request + harmonic aggregate t/s). The 65k q8_0 server-request baseline (28.20) matches llama-bench tg128 (28.16) — parity holds at q8_0/65k too. KV q8_0 costs ~1.5% tg vs f16 at shallow depth (28.16 vs ~28.6). Raw: titan `/tmp/qwen38-ud-mtp-20261014/`.
| Nemotron-3.5 Lightning 30B-A3B | UD-Q4_K_M | 2422 | 132.7 | t16 |
| Qwen3.6-35B-A3B | UD-Q4_K_M | 2140 | 115.3 | full offload, 20.6 GiB |
| LFM2.5-24B-A2B (lfm2moe) | UD-Q4_K_XL | 3407.8 | 190.7 | 2026-10-14; t8/ub2048. Fastest model on either host. @130k depth tg512: **101.1 with f16 KV** (server peak 17.8 GiB @131k) vs 68.3 with q8_0 — f16 KV wins at 128k (+48%); threads t8/t16, ub 512/2048, FA on/off all flat. **Quality verdict: benched it, user rejected it** — terrible outputs on real agent work (s01 capacity-planning task) despite speed; Qwen3.6-MTP is the working default |
| | UD-Q4_K_M-MTP @65k q8_0 | 2180 | 113.4 | 2026-10-14: MTP-embedded rebuild (unsloth MTP-GGUF repo); 21.1 GiB, head costs ~0 |
| | + **MTP draft 2** | | **176.4** | +58% vs same-file baseline (server method); 23.4 GiB peak; code 186.7, prose 166.2; draft 3 = 177.8 mean but 159 on prose |
| Gemma-4 26B-A4B | UD-IQ4_XS | 2674 | 96.6 | 89.8 @ 8K depth |
| gpt-oss-20b | — | — | 142 | from ranking table only |

Threads/ubatch flat on both hosts for these models (t1-t32 measured). FA helps pp on CUDA (+17.6% at 8K depth) but is near-neutral on Vulkan at shallow context.

## Decision models (Clef / d1 / Jev)

Decision models read a `state` + typed questions (`noul` true/false, `choice`, `score`) and return calibrated probabilities for every option in **one forward pass** — no text generation. Detailed per-model write-ups live on titan (`~/models/decision-models-report.md`, `clef-flash.md`, `d1-3b.md`).

**Local lineup** (all benchmarked 2026-10-11 on Titan RTX, llama.cpp `build-clef` v0.6.0-dev b11553):

| model | base | size | 1-q short msg | 3-q short msg | VRAM |
|---|---|---|---:|---:|---|
| Cloudflare Clef-Flash | Qwen3.5-9B + Clef head | 9B Q8_0 | 75.3 ms | 124.7 ms | 9.3 GB |
| Liquid d1-3B | LFM2.5-VL-3B | 3.1B Q8_0 | 12.5 ms | 42.5 ms | 4.5-6.3 GB |
| clef-text-0.6b (CoreML) | Qwen3-0.6B distilled | 0.7B | 47.9 ms (M4 mini) | 114.8 ms | 1.3 GB |

d1-3B is 6x faster on short requests (LFM tokenizer efficiency); parity on long docs. Serving quirks: clef arch needs llama.cpp v0.6.0+, only `/v1/systemone` endpoint, and the whole prompt must fit one micro-batch (`-b`/`-ub` >= prompt). Jev-1.13 is Cloud-hosted only (OpenRouter decisions API — `jev_eval.py`). llmgr: `titan-dec` pseudo-host serves these on port 8095 (`llm start titan-dec d1-3b | clef-flash`).

**Capacity-planning decision model POC (2026-10-15, trained on Titan RTX with Unsloth).** Custom typed-decisions dataset generated from the scenario world model (`~/wrk/decision-poc/gen_dataset.py`): 1,200 rows, 4 questions per record (risk noul / action choice / severity score / defect noul), gold computed by rule. Trained Clef-head via `FastDecisionModel` LoRA r16, 120 steps:

| round | dataset | qwen3.5-0.8B | LFM2.5-2.6B | LFM2-8B-A1B | notes |
|---|---|---:|---:|---:|---|
| r1 | LSQ slope, severity = hidden division | 55.75% (ECE .030) | 55.75% (ECE .030) | — | exact tie: both learned the same decision function — data floor, not capacity |
| r2 | twopoint slope, utilization% printed in state | 59.25% | **62.5%** | — | risk 63→75%, action 54→67%; severity: qwen still 26% (chance), LFM 39% |
| r3 | same as r2 | — | — | **65.5%** | best trained; entire edge is severity (51% vs 39%); risk/action/defect pinned at the same 75/67/69 ceiling for every model — data-bound |

Training cost: 7 min (0.8B) / 25 min (2.6B) on Titan RTX, ~2.7-6 GB VRAM, fp32 head (Turing: no bf16; Qwen3.5/LFM overflow fp16 autocast). Zero-shot decision models (Clef-Flash, d1-3B) on the same holdout: pending. Raw: titan `/mnt/data/decision-poc/`, scripts `~/wrk/decision-poc/`.

## Cross-host insights

- Strix tg ceiling is UMA bandwidth: tg ~ bandwidth / weight-GiB at ~73% efficiency — smaller quant = proportionally faster tg.
- pp is 23-25x cheaper per token than tg on both hosts (SSM hybrid makes long prompts cheap).
- MTP is the only large tg lever measured: 2.30x on strix (draft 3), +61% on titan (draft 2), +74% on titan UD-Q4_K_XL @65k q8_0 (draft 2), +58% on titan Qwen3.6-35B-A3B (draft 2, 112→176 t/s — past the 1.2x threshold in the old notes), +43% on strix Qwen3.6-35B-A3B (draft 3, 57→82 t/s — now 1.7x faster than gpt-oss-120b on ws); optimal draft size differs by hardware and prompt type (strix favors 3, titan favors 2).
- KV q8_0 ~neutral perf; only worthwhile at 32k+ context (halves KV memory). Exception: lfm2moe @130k depth — q8_0 KV costs 34% tg vs f16 (68.3 vs 101.1 t/s on titan); prefer f16 KV when it fits.

## TODO

- [ ] Add `orchestrator.py` + `prompt.md`: deterministic-domain benchmark with deliberately planted flaws. Goal: see which models trip up on the flaws (if any) and gauge general output quality. Model-agnostic (same harness across both hosts' lineups), deterministic grading where possible.
- [ ] Context-length sweep: run pp and tg at increasing ctx depths (e.g. 4k/8k/16k/32k/64k), chart the pp:tg ratio vs ctx to find where each model/host drops off and how steeply.
- [ ] Flag optimization per model for highest throughput: sweep threads/ubatch/FA/KV-type/spec-draft per model per host, lock in a tuned profile.

## Known gaps for future benchmarks

- End-to-end request latency under concurrency (existing serving numbers are 1 and 4 concurrent only).
- MTP at long/occupied context.
- Long-prompt pp decay curves.
- Equal-precision engine comparisons (Vulkan quantized vs vLLM ROCm BF16 conflates precision and engine).
