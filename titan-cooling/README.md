# titan-cooling

Fan control for a **fanless-modded NVIDIA TITAN RTX**: stock blower removed, cooled by a **Morpheus II** air cooler with **2x Noctua slim 120mm** fans, all driven from motherboard PWM headers on an **ASUS ROG STRIX B550-I**. Canonical copy lives on the server at `~/fan-control/`.

**Setup-specific.** The PWM channel mapping below is for this board + cooler combination; adjust for your own layout (`sensors`/`/sys/class/hwmon` to discover channels).

## PWM mapping (verified)

| Channel | Fan |
|---|---|
| `pwm1` | GPU cooler (Noctua #1) |
| `pwm5` | GPU cooler (Noctua #2) |
| `pwm2` | CPU fan |

## Contents

| File | Purpose |
|---|---|
| `fan-control.sh` | Main CLI: `sudo fan-control.sh {auto\|0-100} [all\|cpu\|gpu]` |
| `fan-control-auto.sh` | Temperature-based daemon (3s interval, 5°C hysteresis) |
| `fan-control-auto.conf.example` | Threshold config: 50/75/100% at GPU 60/70/80°C, auto below 45°C |
| `fan-control.service` | systemd unit — pins 75% at boot |
| `fan-control-auto.service` | systemd unit — runs the auto daemon |
| `setup-fan-control.sh` / `install-service.sh` / `install-auto-fan-control.sh` | Installers |
| `llm-fans` | Wrapper: `llm-fans on` = 100% before LLM work, `llm-fans off` = auto after |
| `monitor-temps.sh` | Watch CPU/GPU/chipset/board temps |

## Behavior

- GPU is invisible to the driver's fan controller (no stock blower), so fans must be driven manually or by the daemon — otherwise a loaded-but-uncooled GPU.
- `fan-control.service` pins 75% at boot; the auto daemon overrides it with the threshold ladder above.
- Sustained LLM inference holds 75-100% with stable clocks; below the 45°C floor the box is effectively silent.
- Manual: `sudo fan-control.sh 100 gpu` for max GPU cooling, `sudo fan-control.sh auto` to hand control back to the BIOS.

## Install

```bash
sudo ./install-service.sh          # fixed 75% at boot
# or
sudo ./install-auto-fan-control.sh # temperature-based daemon
```

Edit `/etc/fan-control-auto.conf` to tune thresholds/hysteresis.
