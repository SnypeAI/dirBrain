#!/bin/bash

# Syncthing Auto-Setup Script (No GUI, Multi-Platform)
# This script automatically installs and configures Syncthing on Linux, macOS, and Windows (via WSL)

set -e

SYNC_DIR="$HOME/dirBrain"
SYNCTHING_CONFIG_DIR="$HOME/.config/syncthing"
DEVICE_ID_FILE="$HOME/.syncthing_device_id"
KNOWN_DEVICES_FILE="$HOME/.syncthing_known_devices"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate a random device name
generate_device_name() {
    if command_exists openssl; then
        echo "sync-$(openssl rand -hex 4)"
    else
        echo "sync-$(date +%s | sha256sum | base64 | head -c 8)"
    fi
}

# Install Syncthing
install_syncthing() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        sudo apt-get update
        sudo apt-get install -y apt-transport-https
        curl -s https://syncthing.net/release-key.txt | sudo apt-key add -
        echo "deb https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list
        sudo apt-get update
        sudo apt-get install -y syncthing
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS installation
        if ! command_exists brew; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install syncthing
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ -n "$WSLENV" ]]; then
        # Windows installation (assumes WSL or similar)
        if ! command_exists syncthing; then
            echo "Please install Syncthing for Windows and ensure it's in your PATH."
            echo "Download from: https://github.com/syncthing/syncthing/releases"
            exit 1
        fi
    else
        echo "Unsupported operating system"
        exit 1
    fi
}

# Configure Syncthing
configure_syncthing() {
    # Create sync directory
    mkdir -p "$SYNC_DIR"

    # Generate Syncthing configuration
    syncthing -generate="$SYNCTHING_CONFIG_DIR"

    # Modify config to add our sync folder and disable GUI
    CONFIG_FILE="$SYNCTHING_CONFIG_DIR/config.xml"
    DEVICE_NAME=$(generate_device_name)
    
    # Use xmlstarlet to modify the config
    if ! command_exists xmlstarlet; then
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get install -y xmlstarlet
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install xmlstarlet
        elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ -n "$WSLENV" ]]; then
            echo "Please install xmlstarlet manually for Windows/WSL"
            exit 1
        fi
    fi

    xmlstarlet ed -L \
        -s "/configuration" -t elem -n "folder" \
        -i "/configuration/folder[last()]" -t attr -n "id" -v "dirBrain" \
        -i "/configuration/folder[last()]" -t attr -n "path" -v "$SYNC_DIR" \
        -i "/configuration/folder[last()]" -t attr -n "type" -v "sendreceive" \
        -i "/configuration/folder[last()]" -t attr -n "rescanIntervalS" -v "30" \
        -i "/configuration/folder[last()]" -t attr -n "fsWatcherEnabled" -v "true" \
        -i "/configuration/folder[last()]" -t attr -n "fsWatcherDelayS" -v "10" \
        -d "/configuration/gui" \
        -u "/configuration/options/globalAnnounceEnabled" -v "false" \
        -u "/configuration/options/localAnnounceEnabled" -v "false" \
        -u "/configuration/options/relaysEnabled" -v "false" \
        -u "/configuration/device/@name" -v "$DEVICE_NAME" \
        "$CONFIG_FILE"

    # Extract and save device ID
    DEVICE_ID=$(syncthing -device-id)
    echo "$DEVICE_ID" > "$DEVICE_ID_FILE"

    echo "Syncthing configured with device ID: $DEVICE_ID"
    echo "Device Name: $DEVICE_NAME"
}

# Setup auto-start
setup_autostart() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux auto-start
        sudo systemctl enable syncthing@$USER.service
        sudo systemctl start syncthing@$USER.service
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
        # Windows auto-start (requires manual setup)
        echo "For Windows, please set up Syncthing to run at startup manually."
        echo "You can do this by creating a shortcut to syncthing.exe in the Startup folder."
    fi
}

# Function to add a known device
add_known_device() {
    local device_id=$1
    local device_name=$2
    echo "$device_id $device_name" >> "$KNOWN_DEVICES_FILE"
    
    xmlstarlet ed -L \
        -s "/configuration" -t elem -n "device" \
        -i "/configuration/device[last()]" -t attr -n "id" -v "$device_id" \
        -i "/configuration/device[last()]" -t attr -n "name" -v "$device_name" \
        -s "/configuration/device[last()]" -t elem -n "address" -v "dynamic" \
        -s "/configuration/device[last()]" -t elem -n "autoAcceptFolders" -v "false" \
        -s "/configuration/folder[@id='dirBrain']" -t elem -n "device" -v "" \
        -i "/configuration/folder[@id='dirBrain']/device[last()]" -t attr -n "id" -v "$device_id" \
        "$SYNCTHING_CONFIG_DIR/config.xml"
}

# Function to sync known devices
sync_known_devices() {
    if [ -f "$KNOWN_DEVICES_FILE" ]; then
        while IFS=' ' read -r device_id device_name; do
            if ! grep -q "$device_id" "$SYNCTHING_CONFIG_DIR/config.xml"; then
                add_known_device "$device_id" "$device_name"
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
echo "To connect devices, add their device IDs to $KNOWN_DEVICES_FILE"
echo "Format: <device_id> <device_name>"
echo "Then run this script again to update the configuration"
