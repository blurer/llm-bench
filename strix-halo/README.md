# strix-halo

Fan control + APU power management for the **GMKtec NucBox EVO-X2** (Sixunited AXB35-02 motherboard, Ryzen AI MAX+ 395). Republished from my workstation setup repo (`~/dev/strix_fedora/`).

**Board-specific.** The embedded controller interface here is the Sixunited AXB35-02 only — other Strix Halo machines (Framework Desktop, HP Z2 Mini, etc.) use different ECs and should not run these scripts.

## Contents

| File | Purpose |
|---|---|
| `readme-fancontrol.md` | Full write-up: problem, fix, power modes, fan curves, measured results, throughput impact |
| `setup-fancontrol` | One-time setup: installs DKMS module + systemd service + script |
| `ec-fancontrol` | Apply/status/rebuild CLI (`sudo ec-fancontrol`, `ec-fancontrol status`) |
| `ec-fancontrol.service` | systemd unit — loads module and applies quiet mode + curves on every boot |
| `changelog.md` | History from the source repo |

## Depends on

- Kernel module: https://github.com/cmetz/ec-su_axb35-linux (installed via DKMS; auto-rebuilds on kernel updates)
- Reference: https://strixhalo.wiki/Guides/Sixunited_AXB35/Power_Mode_and_Fan_Control

## Why it matters for benchmarking

- `quiet` mode (STAPM 54W) costs only ~6% generation throughput vs `balanced` (85W) — UMA inference is bandwidth-bound, so the default is silent + cool.
- Fan curves delay ramp-up to 70°C with hysteresis ramp-down, so fans sit at the ~1050 RPM EC floor under normal and sustained LLM load — acoustic baseline is stable between runs.
- Power mode is scriptable per-run at `/sys/class/ec_su_axb35/apu/power_mode` for A/B power testing.

Run `sudo ./setup-fancontrol` on the target machine once; reboots and kernel updates are then fully automatic.
