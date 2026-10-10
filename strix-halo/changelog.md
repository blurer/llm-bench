# Changelog

## 2026-02-24

### llama.cpp
- Rebuilt from source: b7940 → b8146 (Vulkan, native)
- Adds support for Q4_K_XL and other newer quantization types
- Added Qwen3.5 35B.A3B Q4_K_XL (UD) benchmark: 786.6 t/s pp512, 50.6 t/s tg128

## 2026-02-02

### Fan Control
- Installed `ec-su_axb35-linux` kernel module for Sixunited AXB35-02 board
- EC driver exposes fan control, temperature monitoring, and APU power modes via sysfs
- Set APU to quiet power mode (54W STAPM) and custom fan curves (ramp-up at 70°C)
- Fans dropped from ~1500 RPM to ~1040 RPM (hardware minimum)
- Benchmarked quiet vs balanced: +5.9% eval rate for +56% power — not worth it for LLM workloads
- Added `pwr_auto`, `pwr_high`, `pwr` aliases to zshrc
- Added programmatic power mode switching docs (Python snippets)

### SSH
- Fixed remote SSH password auth — Fedora ships `KbdInteractiveAuthentication no` by default
- Set up dual GitHub SSH accounts (blurer/network-audit) via `~/.ssh/config` host aliases
- Added `gc` shell function that auto-routes `git clone` URLs to the correct SSH key

### sysinfo
- Added VRAM usage display (`mem_info_vram_used` / `mem_info_vram_total`)
- Added APU power mode display (reads from EC driver sysfs)
- Added `--no-de` flag to omit DE, WM, Shell, Font, Terminal, Display
- Added `--no-user` flag to omit user@hostname header
- Added `--no-colors` flag to omit color palette blocks

### Docs
- Created `readme-fancontrol.md` — EC driver setup, fan curves, power mode benchmarks
- Created `readme-ssh.md` — password auth fix and dual GitHub account setup
- Updated `readme-sysinfo.md` — new fields and CLI flags
- Updated `info.md` — fan control section, Git SSH multi-account setup
