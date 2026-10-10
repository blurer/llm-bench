#!/bin/bash
#
# Install automatic temperature-based fan control as a systemd service
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Automatic Fan Control Installation ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}Installation steps:${NC}"
echo "1. Copy configuration file (if desired)"
echo "2. Install systemd service"
echo "3. Enable service to start on boot"
echo ""

# Ask about configuration
echo -e "${YELLOW}Would you like to install the example configuration? (y/n)${NC}"
echo "If yes, it will be copied to /etc/fan-control-auto.conf"
echo "You can customize it later to adjust temperature thresholds."
read -r INSTALL_CONFIG

if [[ "$INSTALL_CONFIG" =~ ^[Yy]$ ]]; then
    if [ -f "/etc/fan-control-auto.conf" ]; then
        echo -e "${YELLOW}Configuration file already exists. Backing up to /etc/fan-control-auto.conf.backup${NC}"
        cp /etc/fan-control-auto.conf /etc/fan-control-auto.conf.backup
    fi
    cp "$SCRIPT_DIR/fan-control-auto.conf.example" /etc/fan-control-auto.conf
    echo -e "${GREEN}✓ Configuration installed to /etc/fan-control-auto.conf${NC}"
    echo ""
    echo "You can edit the configuration with:"
    echo "  sudo nano /etc/fan-control-auto.conf"
    echo ""
else
    echo -e "${BLUE}Skipping configuration file installation.${NC}"
    echo "The daemon will use built-in defaults."
    echo ""
fi

# Update the service file path to absolute
SERVICE_FILE="$SCRIPT_DIR/fan-control-auto.service"
TEMP_SERVICE="/tmp/fan-control-auto.service"

# Replace the ExecStart path with absolute path
sed "s|ExecStart=.*|ExecStart=$SCRIPT_DIR/fan-control-auto.sh _monitor|g" "$SERVICE_FILE" > "$TEMP_SERVICE"
sed -i "s|ExecStop=.*|ExecStop=$SCRIPT_DIR/fan-control.sh auto|g" "$TEMP_SERVICE"

# Install systemd service
echo -e "${BLUE}Installing systemd service...${NC}"
cp "$TEMP_SERVICE" /etc/systemd/system/fan-control-auto.service
rm "$TEMP_SERVICE"

# Reload systemd
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd service installed${NC}"
echo ""

# Ask about enabling service
echo -e "${YELLOW}Would you like to enable the service to start on boot? (y/n)${NC}"
read -r ENABLE_SERVICE

if [[ "$ENABLE_SERVICE" =~ ^[Yy]$ ]]; then
    systemctl enable fan-control-auto.service
    echo -e "${GREEN}✓ Service enabled (will start on boot)${NC}"
else
    echo -e "${BLUE}Service installed but not enabled.${NC}"
    echo "You can enable it later with: sudo systemctl enable fan-control-auto.service"
fi
echo ""

# Ask about starting service now
echo -e "${YELLOW}Would you like to start the service now? (y/n)${NC}"
read -r START_SERVICE

if [[ "$START_SERVICE" =~ ^[Yy]$ ]]; then
    systemctl start fan-control-auto.service
    sleep 2
    echo ""
    systemctl status fan-control-auto.service --no-pager -l
    echo ""
    echo -e "${GREEN}✓ Service started${NC}"
else
    echo -e "${BLUE}Service not started.${NC}"
    echo "You can start it later with: sudo systemctl start fan-control-auto.service"
fi

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "  sudo systemctl start fan-control-auto    # Start the service"
echo "  sudo systemctl stop fan-control-auto     # Stop the service"
echo "  sudo systemctl restart fan-control-auto  # Restart after config changes"
echo "  sudo systemctl status fan-control-auto   # Check service status"
echo "  sudo journalctl -u fan-control-auto -f  # View live logs"
echo "  sudo nano /etc/fan-control-auto.conf    # Edit temperature thresholds"
echo ""
echo -e "${YELLOW}Note:${NC} The automatic daemon and manual control (llm-fans/fan-control.sh)"
echo "should not be used simultaneously. If you start the daemon, it will override"
echo "any manual fan speed changes."
echo ""
