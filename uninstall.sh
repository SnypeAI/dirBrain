#!/bin/bash

# Syncthing Removal Script

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Determine OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ -n "$WSLENV" ]]; then
    OS_TYPE="windows"
else
    print_color $RED "Unsupported operating system"
    exit 1
fi

# Determine if running as root
if [ "$EUID" -eq 0 ]; then
    CURRENT_USER="root"
    HOME_DIR="/root"
    SUDO_CMD=""
else
    CURRENT_USER=$(whoami)
    HOME_DIR=$HOME
    SUDO_CMD="sudo"
fi

CONFIG_SAVE_FILE="$HOME_DIR/.syncthing_setup_config"

# Load saved configuration
if [ -f "$CONFIG_SAVE_FILE" ]; then
    source "$CONFIG_SAVE_FILE"
else
    print_color $RED "Configuration file not found. Cannot proceed with removal."
    exit 1
fi

# Function to stop Syncthing
stop_syncthing() {
    print_color $YELLOW "Stopping Syncthing service..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        if [ "$CURRENT_USER" = "root" ]; then
            $SUDO_CMD systemctl stop syncthing.service
            $SUDO_CMD systemctl disable syncthing.service
        else
            $SUDO_CMD systemctl stop syncthing@$CURRENT_USER.service
            $SUDO_CMD systemctl disable syncthing@$CURRENT_USER.service
        fi
    elif [[ "$OS_TYPE" == "macos" ]]; then
        launchctl unload ~/Library/LaunchAgents/com.github.syncthing.syncthing.plist
    elif [[ "$OS_TYPE" == "windows" ]]; then
        # For Windows, we'll just try to kill the process
        taskkill /F /IM syncthing.exe 2>/dev/null || true
    fi
}

# Function to remove Syncthing
remove_syncthing() {
    print_color $YELLOW "Removing Syncthing..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        $SUDO_CMD apt-get remove --purge syncthing
        $SUDO_CMD apt-get autoremove
    elif [[ "$OS_TYPE" == "macos" ]]; then
        brew uninstall syncthing
    elif [[ "$OS_TYPE" == "windows" ]]; then
        print_color $YELLOW "Please uninstall Syncthing manually from the Control Panel."
    fi
}

# Function to remove configuration and data
remove_config_and_data() {
    print_color $YELLOW "Removing Syncthing configuration and data..."
    rm -rf "$SYNCTHING_CONFIG_DIR"
    rm -f "$DEVICE_ID_FILE"
    rm -f "$KNOWN_DEVICES_FILE"
    rm -f "$CONFIG_SAVE_FILE"
    
    # Ask user if they want to remove the sync directory
    read -p "Do you want to remove the sync directory ($SYNC_DIR)? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        rm -rf "$SYNC_DIR"
        print_color $GREEN "Sync directory removed."
    else
        print_color $BLUE "Sync directory kept intact."
    fi
}

# Function to remove autostart configurations
remove_autostart() {
    print_color $YELLOW "Removing autostart configurations..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        $SUDO_CMD rm -f /etc/systemd/system/syncthing.service
        $SUDO_CMD rm -f /etc/systemd/system/syncthing@.service
        $SUDO_CMD systemctl daemon-reload
    elif [[ "$OS_TYPE" == "macos" ]]; then
        rm -f ~/Library/LaunchAgents/com.github.syncthing.syncthing.plist
    elif [[ "$OS_TYPE" == "windows" ]]; then
        rm -f "$APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\start_syncthing.bat"
    fi
}

# Main execution
print_color $YELLOW "Starting Syncthing removal process..."

stop_syncthing
remove_syncthing
remove_config_and_data
remove_autostart

print_color $GREEN "Syncthing has been successfully removed from your system."
print_color $BLUE "If you installed any dependencies specifically for Syncthing (e.g., xmlstarlet), you may want to remove them manually."
print_color $YELLOW "Thank you for using Syncthing!"
