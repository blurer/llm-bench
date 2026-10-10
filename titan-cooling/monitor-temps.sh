#!/bin/bash
#
# Temperature and fan monitoring script
# Shows temps relevant for Titan RTX cooling
#

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ASUS ROG STRIX B550-I + Titan RTX Temperature Monitor     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to get colored temp
get_temp_color() {
    local temp=$1
    local warn_temp=$2
    local crit_temp=$3

    if [ "$temp" -ge "$crit_temp" ]; then
        echo -e "${RED}${temp}°C [CRITICAL]${NC}"
    elif [ "$temp" -ge "$warn_temp" ]; then
        echo -e "${YELLOW}${temp}°C [WARNING]${NC}"
    else
        echo -e "${GREEN}${temp}°C [OK]${NC}"
    fi
}

while true; do
    # Move cursor to home position
    tput cup 4 0

    # Get sensor data
    SENSOR_DATA=$(sensors)

    # Extract temperatures
    CPU_TEMP=$(echo "$SENSOR_DATA" | grep "Tctl:" | awk '{print $2}' | sed 's/[^0-9.]//g' | cut -d. -f1)
    CHIPSET_TEMP=$(echo "$SENSOR_DATA" | grep "Chipset:" | awk '{print $2}' | sed 's/[^0-9.]//g' | cut -d. -f1)
    MB_TEMP=$(echo "$SENSOR_DATA" | grep "Motherboard:" | awk '{print $2}' | sed 's/[^0-9.]//g' | cut -d. -f1)
    FAN_RPM=$(echo "$SENSOR_DATA" | grep "VRM HS:" | awk '{print $2, $3}')

    # Get GPU temp if nvidia-smi is available
    GPU_TEMP=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    fi

    # Display temperatures
    echo -e "${BLUE}CPU Temperature:        ${NC}" $(get_temp_color ${CPU_TEMP:-0} 75 85)
    echo -e "${BLUE}Chipset Temperature:    ${NC}" $(get_temp_color ${CHIPSET_TEMP:-0} 65 75)
    echo -e "${BLUE}Motherboard Temperature:${NC}" $(get_temp_color ${MB_TEMP:-0} 50 60)

    if [ -n "$GPU_TEMP" ]; then
        echo -e "${BLUE}GPU Temperature (RTX):  ${NC}" $(get_temp_color ${GPU_TEMP} 80 88)
    else
        echo -e "${BLUE}GPU Temperature (RTX):  ${NC}${YELLOW}nvidia-smi not found${NC}"
    fi

    echo ""
    echo -e "${BLUE}System Fan (VRM HS):    ${NC}${GREEN}${FAN_RPM} RPM${NC}"

    echo ""
    echo -e "${YELLOW}Recommended fan speeds:${NC}"
    echo "  • Idle/Light work:  AUTO or 50%"
    echo "  • Heavy compute:    75-100%"
    echo "  • LLM inference:    100%"

    echo ""
    echo -e "${BLUE}Press Ctrl+C to exit${NC}"

    sleep 2
done
