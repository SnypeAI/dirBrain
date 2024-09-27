#!/bin/bash

# Universal Secure Self-Updating Syncthing Auto-Setup Script

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
CONFIG_SAVE_FILE="$HOME_DIR/.syncthing_setup_config"

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

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
    print_color $BLUE "Installing Syncthing..."
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
    print_color $GREEN "Syncthing installed successfully."
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

    # Create .known_devices file
    touch "$KNOWN_DEVICES_FILE"
    echo "# Syncthing Known Devices" > "$KNOWN_DEVICES_FILE"
    echo "$DEVICE_ID:$DEVICE_NAME" >> "$KNOWN_DEVICES_FILE"

    print_color $GREEN "Syncthing configured with device ID: $DEVICE_ID"
    print_color $GREEN "Device Name: $DEVICE_NAME"
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

save_config_info() {
    cat > "$CONFIG_SAVE_FILE" <<EOL
SYNC_DIR="$SYNC_DIR"
SYNCTHING_CONFIG_DIR="$SYNCTHING_CONFIG_DIR"
DEVICE_ID_FILE="$DEVICE_ID_FILE"
KNOWN_DEVICES_FILE="$KNOWN_DEVICES_FILE"
EOL
}

create_update_script() {
    cat > "$HOME_DIR/updateDevices.sh" <<EOL
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
    local color=\$1
    local message=\$2
    echo -e "\${color}\${message}\${NC}"
}

# Load configuration
CONFIG_SAVE_FILE="$HOME_DIR/.syncthing_setup_config"
if [ -f "\$CONFIG_SAVE_FILE" ]; then
    source "\$CONFIG_SAVE_FILE"
else
    print_color \$YELLOW "Configuration file not found. Please run the installation script first."
    exit 1
fi

# Function to add known devices to Syncthing config
update_known_devices() {
    print_color \$BLUE "Updating known devices in Syncthing configuration..."
    while IFS=':' read -r device_id device_name; do
        if [[ "\$device_id" != "#"* ]] && ! grep -q "\$device_id" "\$SYNCTHING_CONFIG_DIR/config.xml"; then
            xmlstarlet ed -L \
                -s "/configuration" -t elem -n "device" \
                -i "/configuration/device[last()]" -t attr -n "id" -v "\$device_id" \
                -i "/configuration/device[last()]" -t attr -n "name" -v "\$device_name" \
                -s "/configuration/device[last()]" -t elem -n "address" -v "dynamic" \
                -s "/configuration/device[last()]" -t elem -n "autoAcceptFolders" -v "false" \
                -s "/configuration/folder[@id='dirBrains']" -t elem -n "device" -v "" \
                -i "/configuration/folder[@id='dirBrains']/device[last()]" -t attr -n "id" -v "\$device_id" \
                "\$SYNCTHING_CONFIG_DIR/config.xml"
            print_color \$GREEN "Added device: \$device_name (\$device_id)"
        fi
    done < "\$KNOWN_DEVICES_FILE"
}

# Function to restart Syncthing
restart_syncthing() {
    print_color \$BLUE "Restarting Syncthing..."
    if [[ "\$OSTYPE" == "darwin"* ]]; then
        launchctl stop com.github.syncthing.syncthing
        launchctl start com.github.syncthing.syncthing
    elif [[ "\$OSTYPE" == "linux-gnu"* ]]; then
        if [ "\$(id -u)" -eq 0 ]; then
            systemctl restart syncthing.service
        else
            systemctl --user restart syncthing.service
        fi
    else
        print_color \$YELLOW "Please restart Syncthing manually or reboot your system."
    fi
}

# Main execution
update_known_devices
restart_syncthing

print_color \$GREEN "Syncthing configuration updated and service restarted."
print_color \$YELLOW "Your devices should now be connected. Check Syncthing logs for any issues."
EOL
chmod +x "$HOME_DIR/updateDevices.sh"
    print_color $BLUE "Update script created: $HOME_DIR/updateDevices.sh"
}

# Main execution
clear 
print_color $YELLOW "Starting Syncthing Auto-Setup..."

install_syncthing
configure_syncthing
setup_autostart
sync_known_devices
create_update_script
save_config_info

clear 

DEVICE_ID=$(cat $DEVICE_ID_FILE)
DEVICE_KEY="$DEVICE_ID:$DEVICE_NAME"

print_color $GREEN "\n✅ Syncthing setup complete!"
print_color $BLUE "\n📁 Your sync directory is: $SYNC_DIR"
print_color $BLUE "🆔 Your device ID is: $DEVICE_ID"
print_color $BLUE "🔑 Your device key is: $DEVICE_KEY"
print_color $BLUE "📝 Known devices file: $KNOWN_DEVICES_FILE"

print_color $YELLOW "\n📌 Next steps:"
echo "1. Copy this script to your other devices."
echo "2. Run the script on each device you want to sync."
echo "3. After running on all devices, edit $KNOWN_DEVICES_FILE on each device:"
echo "   - Add the following line to the $KNOWN_DEVICES_FILE on all OTHER devices:"
print_color $GREEN "     $DEVICE_KEY"
echo "   - Repeat this process for each device, adding its key to all other devices."
echo "4. Run the update script on all devices to apply changes:"
print_color $GREEN "     $HOME_DIR/updateDevices.sh"

if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "   - Alternatively, run: launchctl stop com.github.syncthing.syncthing && launchctl start com.github.syncthing.syncthing"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ "$CURRENT_USER" = "root" ]; then
        echo "   - Alternatively, run: systemctl restart syncthing.service"
    else
        echo "   - Alternatively, run: systemctl --user restart syncthing.service"
    fi
else
    echo "   - Alternatively, restart Syncthing manually or reboot your system."
fi

print_color $GREEN "\nSyncthing is now running. Your files will sync automatically once you've added all device keys and run the update script."
print_color $YELLOW "For more information, visit: https://docs.syncthing.net/"

# Save the device key to a file for easy access
echo "$DEVICE_KEY" > "$HOME_DIR/.syncthing_device_key"
print_color $BLUE "\nYour device key has been saved to: $HOME_DIR/.syncthing_device_key"
print_color $YELLOW "You can easily copy it from this file when setting up other devices."