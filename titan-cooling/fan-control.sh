#!/bin/bash
#
# ASUS Fan Control Script for ROG STRIX B550-I
# Controls system fans for cooling a fanless Titan RTX GPU
#
# Usage: sudo ./fan-control.sh [auto|50|75|100] [all|cpu|gpu]
#
# Fan header mapping (verified):
#   pwm1 = GPU cooler fan (intake or exhaust)
#   pwm2 = CPU fan
#   pwm5 = GPU cooler fan (intake or exhaust)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fan control mode and target
MODE="${1:-}"
TARGET="${2:-all}"

# PWM channels per target
CPU_PWMS="pwm2"
GPU_PWMS="pwm1 pwm5"
ALL_PWMS="pwm1 pwm2 pwm5"

# Function to print usage
print_usage() {
    echo "Usage: sudo $0 [auto|50|75|100] [all|cpu|gpu]"
    echo ""
    echo "Speed options:"
    echo "  auto    - Set fans to automatic control (BIOS default)"
    echo "  0-100   - Set fans to that percentage (e.g. 85, 60, 28)"
    echo ""
    echo "Target options (default: all):"
    echo "  all   - All fans (pwm1, pwm2, pwm5)"
    echo "  cpu   - CPU fan only (pwm2)"
    echo "  gpu   - GPU cooler fans only (pwm1, pwm5)"
    echo ""
    echo "Examples:"
    echo "  sudo $0 100        # All fans to max"
    echo "  sudo $0 85 gpu     # GPU cooler fans to 85%"
    echo "  sudo $0 60 cpu     # CPU fan to 60%"
    echo "  sudo $0 auto cpu   # CPU fan back to auto"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0 $MODE"
    exit 1
fi

# Validate arguments
if [ -z "$MODE" ]; then
    print_usage
fi

if [ "$MODE" != "auto" ]; then
    if ! [[ "$MODE" =~ ^[0-9]+$ ]] || [ "$MODE" -lt 0 ] || [ "$MODE" -gt 100 ]; then
        echo -e "${RED}Error: Invalid mode '$MODE' — must be 'auto' or a number 0-100${NC}"
        print_usage
    fi
fi

case "$TARGET" in
    all|cpu|gpu) ;;
    *)
        echo -e "${RED}Error: Invalid target '$TARGET'${NC}"
        print_usage
        ;;
esac

# Resolve target to PWM channels
case "$TARGET" in
    cpu) PWMS="$CPU_PWMS" ;;
    gpu) PWMS="$GPU_PWMS" ;;
    all) PWMS="$ALL_PWMS" ;;
esac

# Convert percentage to PWM value (0-255)
if [ "$MODE" != "auto" ]; then
    PWM_VAL=$(( MODE * 255 / 100 ))
fi

# Display current status
echo -e "${GREEN}=== ASUS Fan Control ===${NC}"
echo -e "Mode: ${YELLOW}$MODE${NC}  Target: ${YELLOW}$TARGET${NC}"
echo ""
sensors | grep -A1 "asusec-isa" || echo "Warning: Cannot read sensor data"
echo ""

# Check for available fan control methods
CONTROL_METHOD=""

# Method 1: Check for ASUS WMI fan control (some ASUS boards)
if [ -d "/sys/devices/platform/asus-nb-wmi" ] || [ -d "/sys/devices/platform/asus_fan" ]; then
    echo -e "${GREEN}Found ASUS WMI fan control${NC}"
    CONTROL_METHOD="wmi"
# Method 2: Check for PWM control
elif ls /sys/class/hwmon/hwmon*/pwm* >/dev/null 2>&1; then
    echo -e "${GREEN}Found PWM fan control${NC}"
    CONTROL_METHOD="pwm"
# Method 3: Check for liquidctl
elif command -v liquidctl >/dev/null 2>&1; then
    echo -e "${GREEN}Found liquidctl${NC}"
    CONTROL_METHOD="liquidctl"
else
    echo -e "${YELLOW}Warning: No direct fan control interface found${NC}"
    CONTROL_METHOD="none"
fi

# Apply fan control based on available method
case "$CONTROL_METHOD" in
    wmi)
        # ASUS WMI control
        WMI_PATH=""
        if [ -d "/sys/devices/platform/asus-nb-wmi" ]; then
            WMI_PATH="/sys/devices/platform/asus-nb-wmi"
        elif [ -d "/sys/devices/platform/asus_fan" ]; then
            WMI_PATH="/sys/devices/platform/asus_fan"
        fi

        # Try to find fan control file
        if [ -f "$WMI_PATH/fan_boost_mode" ]; then
            case "$MODE" in
                auto) echo 0 > "$WMI_PATH/fan_boost_mode" ;;
                50)   echo 1 > "$WMI_PATH/fan_boost_mode" ;;
                75)   echo 1 > "$WMI_PATH/fan_boost_mode" ;;
                100)  echo 2 > "$WMI_PATH/fan_boost_mode" ;;
            esac
            echo -e "${GREEN}Fan mode set to: $MODE${NC}"
        else
            echo -e "${RED}Error: Cannot find fan control interface in WMI${NC}"
            CONTROL_METHOD="none"
        fi
        ;;

    pwm)
        # PWM control
        HWMON="/sys/class/hwmon/hwmon7"
        echo -e "${GREEN}Target: $TARGET (${PWMS})${NC}"
        for pwm_name in $PWMS; do
            PWM_FILE="$HWMON/$pwm_name"
            PWM_ENABLE="${PWM_FILE}_enable"

            if [ ! -f "$PWM_FILE" ]; then
                echo -e "${YELLOW}Warning: $PWM_FILE not found, skipping${NC}"
                continue
            fi

            if [ "$MODE" = "auto" ]; then
                echo 2 > "$PWM_ENABLE" 2>/dev/null || echo 0 > "$PWM_ENABLE"
                echo -e "${GREEN}  $pwm_name → automatic mode${NC}"
            else
                echo 1 > "$PWM_ENABLE"
                echo "$PWM_VAL" > "$PWM_FILE"
                echo -e "${GREEN}  $pwm_name → ${MODE}% (${PWM_VAL}/255)${NC}"
            fi
        done
        ;;

    liquidctl)
        # liquidctl control (for AIO coolers and some motherboards)
        case "$MODE" in
            auto)
                liquidctl set fan speed 20 100 30 100 40 100
                echo -e "${GREEN}Fan set to automatic curve${NC}"
                ;;
            50)
                liquidctl set fan speed 50
                echo -e "${GREEN}Fan set to 50%${NC}"
                ;;
            75)
                liquidctl set fan speed 75
                echo -e "${GREEN}Fan set to 75%${NC}"
                ;;
            100)
                liquidctl set fan speed 100
                echo -e "${GREEN}Fan set to 100%${NC}"
                ;;
        esac
        ;;

    none)
        echo ""
        echo -e "${YELLOW}=== Fan Control Not Available ===${NC}"
        echo ""
        echo "Your ASUS ROG STRIX B550-I motherboard requires additional setup:"
        echo ""
        echo "Option 1: Install ASUS-Linux tools"
        echo "  yay -S asusctl"
        echo "  sudo systemctl enable --now asusd"
        echo ""
        echo "Option 2: Use IT8792E-based control (if your board uses this chip)"
        echo "  yay -S it87-dkms-git"
        echo "  # Add 'acpi_enforce_resources=lax' to kernel parameters"
        echo "  # Edit /etc/default/grub and add to GRUB_CMDLINE_LINUX_DEFAULT"
        echo "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
        echo "  sudo reboot"
        echo ""
        echo "Option 3: Install liquidctl (for some ASUS boards)"
        echo "  sudo pacman -S liquidctl"
        echo ""
        echo "Option 4: Manual BIOS fan curve setup"
        echo "  Boot into BIOS (Delete key) and configure Q-Fan Control"
        echo "  Set aggressive fan curves for all chassis fans"
        echo ""
        echo "For now, please configure your fans in BIOS to run at higher speeds."
        echo ""
        exit 1
        ;;
esac

# Display new status
echo ""
echo -e "${GREEN}=== Current Fan Status ===${NC}"
sensors | grep -A1 "asusec-isa" || echo "Warning: Cannot read sensor data"
echo ""
echo -e "${GREEN}Done!${NC}"
