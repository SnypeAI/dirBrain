#!/bin/bash

# start_syncthing.sh - Script to start Syncthing directly on various operating systems

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to find Syncthing executable
find_syncthing() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS (Homebrew)
        echo "/opt/homebrew/bin/syncthing"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo "$(which syncthing)"
    elif [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ -n "$WSLENV" ]]; then
        # Windows (assuming Syncthing is in PATH)
        echo "syncthing.exe"
    else
        echo ""
    fi
}

# Function to check if Syncthing is already running
is_syncthing_running() {
    pgrep -x syncthing >/dev/null
}

# Find Syncthing executable
SYNCTHING_PATH=$(find_syncthing)

if [ -z "$SYNCTHING_PATH" ]; then
    print_color $RED "Syncthing executable not found. Please ensure it's installed and in your PATH."
    exit 1
fi

# Check if Syncthing is already running
if is_syncthing_running; then
    print_color $YELLOW "Syncthing is already running. Stopping the existing instance..."
    pkill syncthing
    sleep 2
fi

# Start Syncthing
print_color $YELLOW "Starting Syncthing..."
"$SYNCTHING_PATH" -no-browser -no-restart -logflags=0 &

# Wait for Syncthing to start
sleep 5

# Check if Syncthing started successfully
if is_syncthing_running; then
    PID=$(pgrep syncthing)
    print_color $GREEN "Syncthing started successfully. Process ID: $PID"
    print_color $YELLOW "To stop Syncthing, use: kill $PID"
else
    print_color $RED "Failed to start Syncthing. Please check the logs for more information."
fi