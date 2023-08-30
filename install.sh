#!/bin/sh

# Check if the script is already running as root
if [ "$(id -u)" != "0" ]; then
    echo "Not running as root. Elevating privileges..."
    exec sudo "$0" "$@" 
    exit
fi

# Ensure crystal is installed
if ! which crystal > /dev/null; then
    echo "Crystal is not installed. Installing..."
    curl -fsSL https://crystal-lang.org/install.sh | bash
else
    echo "Crystal is already installed."
fi

# Ensure we are up to date
git pull

# Check for existence of files
if [ ! -f ./bin/monitor ] || [ ! -f ./bin/install ]; then
    echo "One or more files are missing. Running shards build..."
    shards build -Dpreview_mt
fi

# Ensure the OS is configured
./bin/install
