#!/bin/bash
#
# Automatic Temperature-Based Fan Control Daemon
# Monitors multiple sensors and adjusts fan speeds dynamically
#
# Usage: sudo ./fan-control-auto.sh [start|stop|status|config]
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration file
CONFIG_FILE="/etc/fan-control-auto.conf"
PID_FILE="/var/run/fan-control-auto.pid"

# Default temperature thresholds (can be overridden in config)
# Format: SENSOR_TEMP_LEVEL=threshold
CPU_TEMP_AUTO=45      # Below this: auto mode
CPU_TEMP_50=60        # At or above: 50% fan speed
CPU_TEMP_75=70        # At or above: 75% fan speed
CPU_TEMP_100=80       # At or above: 100% fan speed

GPU_TEMP_AUTO=45
GPU_TEMP_50=60
GPU_TEMP_75=70
GPU_TEMP_100=80       # GPU gets hot during LLM inference

CHIPSET_TEMP_AUTO=40
CHIPSET_TEMP_50=55
CHIPSET_TEMP_75=65
CHIPSET_TEMP_100=75

MB_TEMP_AUTO=35
MB_TEMP_50=45
MB_TEMP_75=50
MB_TEMP_100=60

# Hysteresis: temperature must drop this many degrees below threshold to decrease fan speed
HYSTERESIS=5

# Check interval in seconds
CHECK_INTERVAL=3

# Load config file if it exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Current fan speed state (to avoid unnecessary writes)
CURRENT_FAN_SPEED=""

# Function to set fan speed (uses fan-control.sh)
set_fan_speed() {
    local speed=$1
    if [ "$speed" != "$CURRENT_FAN_SPEED" ]; then
        echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} Setting fan speed to ${GREEN}$speed${NC}"
        ./fan-control.sh "$speed" >/dev/null 2>&1
        CURRENT_FAN_SPEED="$speed"
    fi
}

# Function to get current temperatures
get_temperatures() {
    SENSOR_DATA=$(sensors 2>/dev/null)

    # Extract temperatures (use 0 if not found)
    CPU_TEMP=$(echo "$SENSOR_DATA" | grep "Tctl:" | awk '{print $2}' | sed 's/[^0-9.]//g' | cut -d. -f1)
    CPU_TEMP=${CPU_TEMP:-0}

    CHIPSET_TEMP=$(echo "$SENSOR_DATA" | grep "Chipset:" | awk '{print $2}' | sed 's/[^0-9.]//g' | cut -d. -f1)
    CHIPSET_TEMP=${CHIPSET_TEMP:-0}

    MB_TEMP=$(echo "$SENSOR_DATA" | grep "Motherboard:" | awk '{print $2}' | sed 's/[^0-9.]//g' | cut -d. -f1)
    MB_TEMP=${MB_TEMP:-0}

    # Get GPU temp if nvidia-smi is available
    GPU_TEMP=0
    if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
        GPU_TEMP=${GPU_TEMP:-0}
    fi
}

# Function to determine required fan speed based on temperatures
determine_fan_speed() {
    local required_speed="auto"
    local reason=""

    # Check each sensor against its thresholds
    # We'll track the highest required speed

    # CPU
    if [ "$CPU_TEMP" -ge "$CPU_TEMP_100" ]; then
        required_speed="100"
        reason="CPU ${CPU_TEMP}°C"
    elif [ "$CPU_TEMP" -ge "$((CPU_TEMP_75 + HYSTERESIS))" ] && [ "$required_speed" != "100" ]; then
        if [ "$required_speed" = "auto" ] || [ "$CPU_TEMP" -ge "$CPU_TEMP_75" ]; then
            required_speed="75"
            reason="CPU ${CPU_TEMP}°C"
        fi
    elif [ "$CPU_TEMP" -ge "$((CPU_TEMP_50 + HYSTERESIS))" ] && [ "$required_speed" != "100" ] && [ "$required_speed" != "75" ]; then
        if [ "$required_speed" = "auto" ] || [ "$CPU_TEMP" -ge "$CPU_TEMP_50" ]; then
            required_speed="50"
            reason="CPU ${CPU_TEMP}°C"
        fi
    fi

    # GPU
    if [ "$GPU_TEMP" -ge "$GPU_TEMP_100" ]; then
        required_speed="100"
        reason="GPU ${GPU_TEMP}°C"
    elif [ "$GPU_TEMP" -ge "$((GPU_TEMP_75 + HYSTERESIS))" ]; then
        if [ "$required_speed" = "auto" ] || [ "$required_speed" = "50" ] || [ "$GPU_TEMP" -ge "$GPU_TEMP_75" ]; then
            if [ "$required_speed" != "100" ]; then
                required_speed="75"
                reason="GPU ${GPU_TEMP}°C"
            fi
        fi
    elif [ "$GPU_TEMP" -ge "$((GPU_TEMP_50 + HYSTERESIS))" ]; then
        if [ "$required_speed" = "auto" ] || [ "$GPU_TEMP" -ge "$GPU_TEMP_50" ]; then
            if [ "$required_speed" != "100" ] && [ "$required_speed" != "75" ]; then
                required_speed="50"
                reason="GPU ${GPU_TEMP}°C"
            fi
        fi
    fi

    # Chipset
    if [ "$CHIPSET_TEMP" -ge "$CHIPSET_TEMP_100" ]; then
        required_speed="100"
        reason="Chipset ${CHIPSET_TEMP}°C"
    elif [ "$CHIPSET_TEMP" -ge "$((CHIPSET_TEMP_75 + HYSTERESIS))" ]; then
        if [ "$required_speed" = "auto" ] || [ "$required_speed" = "50" ] || [ "$CHIPSET_TEMP" -ge "$CHIPSET_TEMP_75" ]; then
            if [ "$required_speed" != "100" ]; then
                required_speed="75"
                reason="Chipset ${CHIPSET_TEMP}°C"
            fi
        fi
    elif [ "$CHIPSET_TEMP" -ge "$((CHIPSET_TEMP_50 + HYSTERESIS))" ]; then
        if [ "$required_speed" = "auto" ] || [ "$CHIPSET_TEMP" -ge "$CHIPSET_TEMP_50" ]; then
            if [ "$required_speed" != "100" ] && [ "$required_speed" != "75" ]; then
                required_speed="50"
                reason="Chipset ${CHIPSET_TEMP}°C"
            fi
        fi
    fi

    # Motherboard
    if [ "$MB_TEMP" -ge "$MB_TEMP_100" ]; then
        required_speed="100"
        reason="Motherboard ${MB_TEMP}°C"
    elif [ "$MB_TEMP" -ge "$((MB_TEMP_75 + HYSTERESIS))" ]; then
        if [ "$required_speed" = "auto" ] || [ "$required_speed" = "50" ] || [ "$MB_TEMP" -ge "$MB_TEMP_75" ]; then
            if [ "$required_speed" != "100" ]; then
                required_speed="75"
                reason="Motherboard ${MB_TEMP}°C"
            fi
        fi
    elif [ "$MB_TEMP" -ge "$((MB_TEMP_50 + HYSTERESIS))" ]; then
        if [ "$required_speed" = "auto" ] || [ "$MB_TEMP" -ge "$MB_TEMP_50" ]; then
            if [ "$required_speed" != "100" ] && [ "$required_speed" != "75" ]; then
                required_speed="50"
                reason="Motherboard ${MB_TEMP}°C"
            fi
        fi
    fi

    echo "$required_speed|$reason"
}

# Main monitoring loop
monitor_loop() {
    echo -e "${GREEN}=== Automatic Fan Control Started ===${NC}"
    echo -e "${BLUE}Configuration:${NC}"
    echo "  CPU: auto<${CPU_TEMP_AUTO}°C | 50%=${CPU_TEMP_50}°C | 75%=${CPU_TEMP_75}°C | 100%=${CPU_TEMP_100}°C"
    echo "  GPU: auto<${GPU_TEMP_AUTO}°C | 50%=${GPU_TEMP_50}°C | 75%=${GPU_TEMP_75}°C | 100%=${GPU_TEMP_100}°C"
    echo "  Chipset: auto<${CHIPSET_TEMP_AUTO}°C | 50%=${CHIPSET_TEMP_50}°C | 75%=${CHIPSET_TEMP_75}°C | 100%=${CHIPSET_TEMP_100}°C"
    echo "  Motherboard: auto<${MB_TEMP_AUTO}°C | 50%=${MB_TEMP_50}°C | 75%=${MB_TEMP_75}°C | 100%=${MB_TEMP_100}°C"
    echo "  Hysteresis: ${HYSTERESIS}°C"
    echo "  Check interval: ${CHECK_INTERVAL}s"
    echo ""

    while true; do
        get_temperatures

        # Determine required fan speed
        result=$(determine_fan_speed)
        required_speed=$(echo "$result" | cut -d'|' -f1)
        reason=$(echo "$result" | cut -d'|' -f2)

        # Display current status
        status_line="CPU:${CPU_TEMP}°C GPU:${GPU_TEMP}°C Chipset:${CHIPSET_TEMP}°C MB:${MB_TEMP}°C"
        if [ -n "$reason" ]; then
            status_line="$status_line → Fan:${required_speed} (${reason})"
        else
            status_line="$status_line → Fan:${required_speed}"
        fi
        echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $status_line"

        # Set fan speed if needed
        set_fan_speed "$required_speed"

        sleep "$CHECK_INTERVAL"
    done
}

# Function to start daemon
start_daemon() {
    if [ -f "$PID_FILE" ]; then
        if ps -p $(cat "$PID_FILE") > /dev/null 2>&1; then
            echo -e "${YELLOW}Fan control daemon is already running (PID: $(cat $PID_FILE))${NC}"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi

    echo -e "${GREEN}Starting automatic fan control daemon...${NC}"
    nohup "$0" _monitor >> /var/log/fan-control-auto.log 2>&1 &
    echo $! > "$PID_FILE"
    echo -e "${GREEN}Daemon started (PID: $(cat $PID_FILE))${NC}"
    echo "Log file: /var/log/fan-control-auto.log"
}

# Function to stop daemon
stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Fan control daemon is not running${NC}"
        exit 1
    fi

    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo -e "${YELLOW}Stopping fan control daemon (PID: $PID)...${NC}"
        kill "$PID"
        rm -f "$PID_FILE"
        echo -e "${GREEN}Daemon stopped${NC}"
        echo -e "${BLUE}Resetting fans to auto mode...${NC}"
        ./fan-control.sh auto
    else
        echo -e "${YELLOW}Daemon is not running (stale PID file)${NC}"
        rm -f "$PID_FILE"
    fi
}

# Function to show status
show_status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo -e "${GREEN}Fan control daemon is running (PID: $PID)${NC}"
            echo ""
            echo "Recent log entries:"
            tail -n 10 /var/log/fan-control-auto.log 2>/dev/null || echo "No log file found"
        else
            echo -e "${RED}Daemon is not running (stale PID file)${NC}"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "${YELLOW}Fan control daemon is not running${NC}"
    fi
}

# Function to show/edit config
show_config() {
    echo -e "${GREEN}=== Fan Control Configuration ===${NC}"
    echo ""
    echo "Configuration file: $CONFIG_FILE"
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        echo "Current configuration:"
        cat "$CONFIG_FILE"
    else
        echo -e "${YELLOW}No configuration file found. Using defaults.${NC}"
        echo ""
        echo "To create a custom configuration, create $CONFIG_FILE with:"
        echo ""
        cat <<'EOF'
# Temperature thresholds (°C)
CPU_TEMP_AUTO=45
CPU_TEMP_50=60
CPU_TEMP_75=70
CPU_TEMP_100=80

GPU_TEMP_AUTO=45
GPU_TEMP_50=60
GPU_TEMP_75=70
GPU_TEMP_100=80

CHIPSET_TEMP_AUTO=40
CHIPSET_TEMP_50=55
CHIPSET_TEMP_75=65
CHIPSET_TEMP_100=75

MB_TEMP_AUTO=35
MB_TEMP_50=45
MB_TEMP_75=50
MB_TEMP_100=60

# Hysteresis (°C) - prevents oscillation
HYSTERESIS=5

# Check interval (seconds)
CHECK_INTERVAL=3
EOF
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ] && [ "$1" != "config" ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0 $1"
    exit 1
fi

# Parse command
case "${1:-}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon
        ;;
    status)
        show_status
        ;;
    config)
        show_config
        ;;
    _monitor)
        # Internal command: run monitoring loop
        monitor_loop
        ;;
    *)
        echo "Usage: sudo $0 {start|stop|restart|status|config}"
        echo ""
        echo "Commands:"
        echo "  start   - Start automatic fan control daemon"
        echo "  stop    - Stop daemon and reset fans to auto"
        echo "  restart - Restart the daemon"
        echo "  status  - Show daemon status and recent activity"
        echo "  config  - Show/edit temperature thresholds"
        echo ""
        exit 1
        ;;
esac
