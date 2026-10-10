#!/bin/bash
#
# Setup script for ASUS ROG STRIX B550-I fan control
# This will install the necessary drivers for fan control
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== ASUS Fan Control Setup ===${NC}"
echo ""
echo "This script will set up fan control for your ASUS ROG STRIX B550-I motherboard."
echo ""

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}Error: This script is designed for Arch Linux${NC}"
    exit 1
fi

# Check if yay is installed
if ! command -v yay >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing yay (AUR helper)...${NC}"
    sudo pacman -S --needed git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
fi

echo -e "${BLUE}Step 1: Installing IT87 driver${NC}"
echo "This driver provides fan control for ASUS motherboards with IT87xx chips"
echo ""

if yay -Q it87-dkms-git >/dev/null 2>&1; then
    echo -e "${GREEN}it87-dkms-git is already installed${NC}"
else
    echo "Installing it87-dkms-git..."
    yay -S --noconfirm it87-dkms-git
fi

echo ""
echo -e "${BLUE}Step 2: Configuring kernel parameters${NC}"
echo ""

# Check if acpi_enforce_resources=lax is already set
if grep -q "acpi_enforce_resources=lax" /etc/default/grub; then
    echo -e "${GREEN}Kernel parameter already configured${NC}"
else
    echo "Adding 'acpi_enforce_resources=lax' to kernel parameters..."

    # Backup grub config
    sudo cp /etc/default/grub /etc/default/grub.backup

    # Add parameter
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_enforce_resources=lax"/' /etc/default/grub

    # Clean up any double spaces
    sudo sed -i 's/  */ /g' /etc/default/grub

    echo -e "${GREEN}Kernel parameter added${NC}"

    # Update GRUB
    echo "Updating GRUB configuration..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

echo ""
echo -e "${BLUE}Step 3: Loading IT87 module${NC}"
echo ""

# Try to load the module
if lsmod | grep -q it87; then
    echo -e "${GREEN}IT87 module already loaded${NC}"
else
    echo "Loading IT87 module..."
    sudo modprobe it87 force_id=0x8628 || echo -e "${YELLOW}Module load failed - will work after reboot${NC}"
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: You must reboot for changes to take effect${NC}"
echo ""
echo "After reboot, test the fan control:"
echo "  sudo ./fan-control.sh 100"
echo ""
echo "Would you like to reboot now? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    sudo reboot
else
    echo "Please reboot manually when ready:"
    echo "  sudo reboot"
fi
