#!/bin/bash

# updateDevices.sh - Script to update Syncthing configuration and restart the service

set -e

# ANSI color codes
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

# Load configuration
CONFIG_SAVE_FILE="$HOME/.syncthing_setup_config"
if [ -f "$CONFIG_SAVE_FILE" ]; then
    source "$CONFIG_SAVE_FILE"
else
    print_color $YELLOW "Configuration file not found. Please run the installation script first."
    exit 1
fi

# Function to add known devices to Syncthing config
update_known_devices() {
    print_color $BLUE "Updating known devices in Syncthing configuration..."
    while IFS=':' read -r device_id device_name; do
        if [[ "$device_id" != "#"* ]] && ! grep -q "$device_id" "$SYNCTHING_CONFIG_DIR/config.xml"; then
            xmlstarlet ed -L \
                -s "/configuration" -t elem -n "device" \
                -i "/configuration/device[last()]" -t attr -n "id" -v "$device_id" \
                -i "/configuration/device[last()]" -t attr -n "name" -v "$device_name" \
                -s "/configuration/device[last()]" -t elem -n "address" -v "dynamic" \
                -s "/configuration/device[last()]" -t elem -n "autoAcceptFolders" -v "false" \
                -s "/configuration/folder[@id='dirBrain']" -t elem -n "device" -v "" \
                -i "/configuration/folder[@id='dirBrain']/device[last()]" -t attr -n "id" -v "$device_id" \
                "$SYNCTHING_CONFIG_DIR/config.xml"
            print_color $GREEN "Added device: $device_name ($device_id)"
        fi
    done < "$KNOWN_DEVICES_FILE"
}

# Function to restart Syncthing
restart_syncthing() {
    print_color $BLUE "Restarting Syncthing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        launchctl stop com.github.syncthing.syncthing
        launchctl start com.github.syncthing.syncthing
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ "$(id -u)" -eq 0 ]; then
            systemctl restart syncthing.service
        else
            systemctl --user restart syncthing.service
        fi
    else
        print_color $YELLOW "Please restart Syncthing manually or reboot your system."
    fi
}

# Main execution
update_known_devices
restart_syncthing

print_color $GREEN "Syncthing configuration updated and service restarted."
print_color $YELLOW "Your devices should now be connected. Check Syncthing logs for any issues."
