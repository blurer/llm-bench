#!/bin/bash
#
# Install systemd service to set fan speed on boot
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Installing fan control systemd service${NC}"
echo ""

# Copy service file
sudo cp fan-control.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable fan-control.service

echo -e "${GREEN}Service installed and enabled${NC}"
echo ""
echo "The fans will be set to 75% on every boot."
echo ""
echo "To change the default speed, edit:"
echo "  /etc/systemd/system/fan-control.service"
echo "And change the ExecStart line to use 50, 75, or 100"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status fan-control    # Check service status"
echo "  sudo systemctl start fan-control     # Start now"
echo "  sudo systemctl stop fan-control      # Stop service"
echo "  sudo systemctl disable fan-control   # Disable on boot"
