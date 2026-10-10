# GMKtec Strix Halo (AMD AI 395 Max+) - Fan Control Fix

**Status: FIXED**

## Hardware
- GMKtec NucBox EVO-X2 (Mini PC chassis)
- Sixunited AXB35-02 motherboard
- 2x CPU fans, 1x system fan (unused, reads 0 RPM)
- Fan speed controlled entirely by the embedded controller (EC) — no PWM interface exposed to Linux

## Problem
Fans audibly loud at idle despite BIOS set to quiet profile. Root causes:
- The BIOS "quiet" profile is not exposed to Linux via ACPI platform profiles
- Default `tuned` profile (`balanced`) sets EPP to `balance_performance`, keeping CPU/GPU power high
- GPU idles at ~39W due to the 64GB VRAM allocation keeping HBM memory controllers active
- CPU Tctl was 62°C at idle, triggering the EC to run fans at ~1500 RPM
- No fan control interface available to Linux (no sysfs PWM, no ec_sys module on this kernel)

### What partially helped but wasn't enough
- Switching `tuned` to `balanced-battery` dropped Tctl to ~52°C and GPU PPT to ~23W
- `ryzenadj` could set STAPM/PPT limits but settings are volatile and don't control the EC fan curve
- The EC's default fan curve ramps up at 60°C, which idle temps still exceeded

## Fix
Use the `ec-su_axb35-linux` kernel module — a driver specifically for the Sixunited AXB35-02 board that exposes EC fan control, temperature monitoring, and APU power modes via sysfs.

- Driver repo: https://github.com/cmetz/ec-su_axb35-linux
- Wiki reference: https://strixhalo.wiki/Guides/Sixunited_AXB35/Power_Mode_and_Fan_Control

## Setup (One-Time)

Run the setup script to install DKMS (auto-rebuilds the module on kernel updates) and a systemd service (auto-applies fan curves on boot):

```bash
sudo ./setup-fancontrol
```

This installs:
- **DKMS** — automatically rebuilds `ec_su_axb35` whenever `dnf` installs a new kernel
- **systemd service** (`ec-fancontrol.service`) — loads the module and applies quiet mode + fan curves on every boot
- **`ec-fancontrol`** script to `/usr/local/bin/`

After setup, kernel updates and reboots are fully automatic. No manual intervention needed.

Verify:
```bash
dkms status                           # should show ec_su_axb35/0.1: installed
systemctl status ec-fancontrol        # should show active (exited)
```

## Quick Start

The `ec-fancontrol` script can also be used manually:

```bash
sudo ec-fancontrol                    # apply quiet mode + fan curves (default)
sudo ec-fancontrol -m balanced        # apply balanced mode instead
sudo ec-fancontrol rebuild            # rebuild module (if not using DKMS)
ec-fancontrol status                  # check current state (no root needed)
ec-fancontrol --help                  # full usage info
```

## Manual Steps (Reference)

The script automates all of these. Documented here for understanding.

### 1. Build and install the kernel module
```bash
cd ~/dev/ec-su_axb35-linux
make
sudo make install
```
Secure Boot must be disabled (it is). The module signing step will fail without a signing key, which is fine.

Must be rebuilt after kernel updates:
```bash
cd ~/dev/ec-su_axb35-linux && make clean && make && sudo make install
```

### 2. Load the module
```bash
sudo modprobe ec_su_axb35
```
Verify: `ls /sys/class/ec_su_axb35/` should show `apu fan1 fan2 fan3 temp1`.

### 3. Set quiet power mode
```bash
echo quiet | sudo tee /sys/class/ec_su_axb35/apu/power_mode
```

### 4. Set custom fan curves
```bash
# Ramp-up thresholds (°C) for fan levels 1-5
echo "70,80,88,95,97" | sudo tee /sys/class/ec_su_axb35/fan1/rampup_curve
echo "70,80,88,95,97" | sudo tee /sys/class/ec_su_axb35/fan2/rampup_curve

# Ramp-down thresholds (hysteresis to prevent fan hunting)
echo "60,65,85,93,96" | sudo tee /sys/class/ec_su_axb35/fan1/rampdown_curve
echo "60,65,85,93,96" | sudo tee /sys/class/ec_su_axb35/fan2/rampdown_curve

# Enable curve mode
echo curve | sudo tee /sys/class/ec_su_axb35/fan1/mode
echo curve | sudo tee /sys/class/ec_su_axb35/fan2/mode
```

Default curves were `60,70,83,95,97` (ramp-up) and `40,50,80,94,96` (ramp-down). The custom curves delay fan ramp-up to 70°C so idle temps (~55°C) stay below the threshold.

## Power Modes

| Mode        | STAPM | Fast PPT | Slow PPT |
|-------------|-------|----------|----------|
| quiet       | 54W   | 100W     | 54W      |
| balanced    | 85W   | 120W     | 120W     |
| performance | 120W  | 140W     | 120W     |

## Results
| Metric    | Before (no driver) | After (EC quiet + custom curve) |
|-----------|--------------------|---------------------------------|
| CPU Tctl  | 62°C               | ~55°C                           |
| GPU PPT   | 39W                | ~26W                            |
| Fan1 RPM  | ~1500              | ~1040 (hardware minimum)        |
| Fan2 RPM  | ~1500              | ~1040 (hardware minimum)        |

## Sysfs Reference
All controls at `/sys/class/ec_su_axb35/`:

| Path | R/W | Description |
|------|-----|-------------|
| `apu/power_mode` | RW | quiet, balanced, performance |
| `temp1/temp` | R | CPU temperature (°C) |
| `fan{1,2,3}/rpm` | R | Current fan speed |
| `fan{1,2,3}/mode` | RW | auto, fixed, curve |
| `fan{1,2,3}/level` | RW | Speed level 0-5 (used in fixed mode, read in curve mode) |
| `fan{1,2,3}/rampup_curve` | RW | 5 comma-separated temps (°C) for levels 1-5 |
| `fan{1,2,3}/rampdown_curve` | RW | 5 comma-separated temps (°C) for levels 1-5 |

## Benchmarks (Ollama — qwen3:120b via Vulkan)

| Mode | STAPM | GPU PPT | Eval Rate | Prompt Eval |
|------|-------|---------|-----------|-------------|
| Quiet (54W) | 54W | ~55W | 27.86 t/s | 115.37 t/s |
| Balanced (85W) | 85W | ~85W | 29.51 t/s | 124.53 t/s |

Balanced gives **+5.9% eval rate for +56% more power**. Large models are memory-bandwidth-bound (shuffling 64GB of weights through HBM), not compute-bound, so extra power doesn't help much. Quiet mode is recommended for LLM workloads.

Reference: https://strixhalo.wiki/Guides/Power_Modes_and_Performance

## Programmatic Power Mode Switching

For scripts that need to temporarily boost performance (requires root or sudoers rule):

```python
from pathlib import Path

POWER_MODE = Path("/sys/class/ec_su_axb35/apu/power_mode")

def set_power(mode: str):
    """Set APU power mode. Valid modes: quiet, balanced, performance"""
    POWER_MODE.write_text(mode)

# Usage
set_power("balanced")
# ... run workload ...
set_power("quiet")
```

To run without root, add a sudoers rule:
```bash
# /etc/sudoers.d/power-mode
youruser ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/class/ec_su_axb35/apu/power_mode
```

Then use subprocess instead:
```python
import subprocess

def set_power(mode: str):
    subprocess.run(
        ["sudo", "tee", "/sys/class/ec_su_axb35/apu/power_mode"],
        input=mode.encode(), stdout=subprocess.DEVNULL
    )
```

Shell aliases are also available in `~/.zshrc`:
```bash
power-quiet        # 54W STAPM
power-balanced     # 85W STAPM
power-performance  # 120W STAPM
power-status       # show current mode
```

## Notes
- **Persistent across reboots and kernel updates.** DKMS rebuilds the module automatically on kernel updates; the systemd service applies fan curves on boot.
- **Manual rebuild** is still available via `sudo ec-fancontrol rebuild` if needed.
- **Hardware fan floor is ~1040 RPM.** The EC will not allow fans to fully stop regardless of mode or level.
- **Fan3 is unused** on this chassis (reads 0 RPM).
- **Unloading the module** (`sudo rmmod ec_su_axb35`) reverts everything to BIOS defaults immediately.
- **tuned profile** was reverted to `balanced` — the EC quiet power mode handles APU power management directly and is the proper mechanism for this board.
- The `ryzenadj` tool was tested but is unnecessary with the EC driver. It can still be useful for temporary per-session tweaks if needed (`/tmp/RyzenAdj/build/ryzenadj`).
