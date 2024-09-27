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

# Find Syncthing executable
SYNCTHING_PATH=$(find_syncthing)

if [ -z "$SYNCTHING_PATH" ]; then
    print_color $RED "Syncthing executable not found. Please ensure it's installed and in your PATH."
    exit 1
fi

# Start Syncthing
print_color $YELLOW "Starting Syncthing..."
"$SYNCTHING_PATH" -no-browser &

print_color $GREEN "Syncthing started. Process ID: $!"
print_color $YELLOW "To stop Syncthing, use: kill $!"