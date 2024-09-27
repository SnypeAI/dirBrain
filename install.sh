#!/bin/bash

# Universal Secure Self-Updating Syncthing Auto-Setup Script
# This script automatically installs, configures Syncthing, and maintains a shared list of all devices
# It works on Linux, macOS, and Windows (via WSL or Git Bash), and supports both root and non-root users

set -e

# Determine OS and set appropriate commands
if [[ "$OSTYPE" == "darwin"* ]]; then
    SUDO_CMD=""
    INSTALL_CMD="brew install"
    UPDATE_CMD="brew update"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    SUDO_CMD="sudo"
    INSTALL_CMD="apt-get install -y"
    UPDATE_CMD="apt-get update"
elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ -n "$WSLENV" ]]; then
    SUDO_CMD=""
    INSTALL_CMD="pacman -S --noconfirm"
    UPDATE_CMD="pacman -Syu --noconfirm"
else
    echo "Unsupported operating system"
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
fi

SYNC_DIR="$HOME_DIR/dirBrains"
SYNCTHING_CONFIG_DIR="$HOME_DIR/.config/syncthing"
DEVICE_ID_FILE="$HOME_DIR/.syncthing_device_id"
KNOWN_DEVICES_FILE="$SYNC_DIR/.known_devices"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate a secure device name
generate_secure_device_name() {
    local hostname=$(hostname)
    local timestamp=$(date +%s)
    local random_string=$(openssl rand -hex 4)
    echo "${hostname}-${timestamp}-${random_string}"
}

# Install Syncthing
install_syncthing() {
    if command_exists syncthing; then
        echo "Syncthing is already installed. Updating..."
        $SUDO_CMD $UPDATE_CMD
        $SUDO_CMD $INSTALL_CMD syncthing
    else
        echo "Installing Syncthing..."
        $SUDO_CMD $UPDATE_CMD
        $SUDO_CMD $INSTALL_CMD syncthing
    fi

    # Install xmlstarlet if not present
    if ! command_exists xmlstarlet; then
        echo "Installing xmlstarlet..."
        $SUDO_CMD $INSTALL_CMD xmlstarlet
    fi
}

# Configure Syncthing
configure_syncthing() {
    # Create sync directory
    mkdir -p "$SYNC_DIR"

    # Stop any running Syncthing instance
    if [[ "$OSTYPE" == "darwin"* ]]; then
        launchctl unload ~/Library/LaunchAgents/com.github.syncthing.syncthing.plist 2>/dev/null || true
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        $SUDO_CMD systemctl stop syncthing@$CURRENT_USER.service 2>/dev/null || true
        $SUDO_CMD systemctl stop syncthing.service 2>/dev/null || true
    fi

    # Remove existing configuration to ensure clean setup
    rm -rf "$SYNCTHING_CONFIG_DIR"

    # Generate new Syncthing configuration
    syncthing -generate="$SYNCTHING_CONFIG_DIR"

    # Modify config to add our sync folder and disable GUI
    CONFIG_FILE="$SYNCTHING_CONFIG_DIR/config.xml"
    DEVICE_NAME=$(generate_secure_device_name)
    
    xmlstarlet ed -L \
        -s "/configuration" -t elem -n "folder" \
        -i "/configuration/folder[last()]" -t attr -n "id" -v "dirBrains" \
        -i "/configuration/folder[last()]" -t attr -n "path" -v "$SYNC_DIR" \
        -i "/configuration/folder[last()]" -t attr -n "type" -v "sendreceive" \
        -i "/configuration/folder[last()]" -t attr -n "rescanIntervalS" -v "30" \
        -i "/configuration/folder[last()]" -t attr -n "fsWatcherEnabled" -v "true" \
        -i "/configuration/folder[last()]" -t attr -n "fsWatcherDelayS" -v "10" \
        -d "/configuration/gui" \
        -u "/configuration/options/globalAnnounceEnabled" -v "false" \
        -u "/configuration/options/localAnnounceEnabled" -v "false" \
        -u "/configuration/options/relaysEnabled" -v "false" \
        -u "/configuration/options/natEnabled" -v "false" \
        -u "/configuration/options/urAccepted" -v "-1" \
        -u "/configuration/device/@name" -v "$DEVICE_NAME" \
        "$CONFIG_FILE"

    # Extract and save device ID
    DEVICE_ID=$(syncthing -device-id)
    echo "$DEVICE_ID" > "$DEVICE_ID_FILE"

    echo "Syncthing configured with device ID: $DEVICE_ID"
    echo "Device Name: $DEVICE_NAME"

    # Add this device to the known devices file
    add_device_to_known_devices "$DEVICE_ID" "$DEVICE_NAME"
}

# Setup auto-start
setup_autostart() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux auto-start
        if [ "$CURRENT_USER" = "root" ]; then
            $SUDO_CMD tee /etc/systemd/system/syncthing.service > /dev/null <<EOL
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization
Documentation=man:syncthing(1)
After=network.target

[Service]
ExecStart=/usr/bin/syncthing -no-browser -no-restart -logflags=0
Restart=on-failure
RestartSec=5
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

[Install]
WantedBy=multi-user.target
EOL
            $SUDO_CMD systemctl daemon-reload
            $SUDO_CMD systemctl enable syncthing.service
            $SUDO_CMD systemctl start syncthing.service
        else
            $SUDO_CMD tee /etc/systemd/system/syncthing@.service > /dev/null <<EOL
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization for %I
Documentation=man:syncthing(1)
After=network.target

[Service]
User=%i
ExecStart=/usr/bin/syncthing -no-browser -no-restart -logflags=0
Restart=on-failure
RestartSec=5
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

[Install]
WantedBy=multi-user.target
EOL
            $SUDO_CMD systemctl daemon-reload
            $SUDO_CMD systemctl enable syncthing@$CURRENT_USER.service
            $SUDO_CMD systemctl start syncthing@$CURRENT_USER.service
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS auto-start
        mkdir -p ~/Library/LaunchAgents
        cat > ~/Library/LaunchAgents/com.github.syncthing.syncthing.plist <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.github.syncthing.syncthing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/syncthing</string>
        <string>-no-browser</string>
        <string>-no-restart</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOL
        launchctl load ~/Library/LaunchAgents/com.github.syncthing.syncthing.plist
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ -n "$WSLENV" ]]; then
        # Windows auto-start (creates a startup script)
        STARTUP_DIR="$APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        echo "start /B syncthing -no-console -no-browser" > "$STARTUP_DIR\start_syncthing.bat"
        echo "Windows auto-start script created in Startup folder."
    fi
}

# Function to add a known device to Syncthing config
add_known_device() {
    local device_id=$1
    local device_name=$2
    
    xmlstarlet ed -L \
        -s "/configuration" -t elem -n "device" \
        -i "/configuration/device[last()]" -t attr -n "id" -v "$device_id" \
        -i "/configuration/device[last()]" -t attr -n "name" -v "$device_name" \
        -s "/configuration/device[last()]" -t elem -n "address" -v "dynamic" \
        -s "/configuration/device[last()]" -t elem -n "autoAcceptFolders" -v "false" \
        -s "/configuration/folder[@id='dirBrains']" -t elem -n "device" -v "" \
        -i "/configuration/folder[@id='dirBrains']/device[last()]" -t attr -n "id" -v "$device_id" \
        "$SYNCTHING_CONFIG_DIR/config.xml"
}

# Function to add device to the known devices file
add_device_to_known_devices() {
    local device_id=$1
    local device_name=$2
    
    if [ ! -f "$KNOWN_DEVICES_FILE" ]; then
        echo "# Syncthing Known Devices" > "$KNOWN_DEVICES_FILE"
    fi

    if ! grep -q "$device_id" "$KNOWN_DEVICES_FILE"; then
        echo "$device_id:$device_name" >> "$KNOWN_DEVICES_FILE"
    fi
}

# Function to sync known devices
sync_known_devices() {
    if [ -f "$KNOWN_DEVICES_FILE" ]; then
        while IFS=':' read -r device_id device_name; do
            if [[ "$device_id" != "#"* ]]; then
                if ! grep -q "$device_id" "$SYNCTHING_CONFIG_DIR/config.xml"; then
                    add_known_device "$device_id" "$device_name"
                    echo "Added device: $device_name ($device_id)"
                fi
            fi
        done < "$KNOWN_DEVICES_FILE"
    fi
}

# Main execution
install_syncthing
configure_syncthing
setup_autostart
sync_known_devices

echo "Syncthing setup complete. The sync directory is: $SYNC_DIR"
echo "Your device ID is: $(cat $DEVICE_ID_FILE)"
echo "Known devices have been automatically added to your Syncthing configuration."
echo "The list of all known devices is maintained in $KNOWN_DEVICES_FILE"
echo "To add more devices, run this script on other machines."

# Start Syncthing
if [[ "$OSTYPE" == "darwin"* ]]; then
    launchctl start com.github.syncthing.syncthing
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ "$CURRENT_USER" = "root" ]; then
        $SUDO_CMD systemctl start syncthing.service
    else
        $SUDO_CMD systemctl start syncthing@$CURRENT_USER.service
    fi
else
    echo "Please start Syncthing manually or reboot your system."
fi

echo "Syncthing should now be running. You may need to reboot your system for all changes to take effect."
