#!/bin/sh

# Ensure we are up to date
git pull

# Ensure crystal is installed
if ! which crystal > /dev/null; then
    echo "Crystal is not installed. Installing..."
    curl -fsSL https://crystal-lang.org/install.sh | sudo bash
else
    echo "Crystal is already installed."
fi

# Check for existence of files
if [ ! -f ./bin/monitor ] || [ ! -f ./bin/install ]; then
    echo "One or more files are missing. Running shards build..."
    shards build -Dpreview_mt
fi

# Ensure the OS is configured
sudo ./bin/install
