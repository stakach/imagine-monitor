#!/bin/sh

# Ensure we are up to date
git pull
sudo apt-get update

echo "Installing required packages..."
sudo apt-get install -y wget curl build-essential make cmake \
                        gnupg v4l-utils v4l2loopback-dkms ffmpeg \
                        libswscale-dev usbutils opencl-headers \
                        libgles2-mesa libgles2-mesa-dev clinfo \
                        ocl-icd-libopencl1 ocl-icd-opencl-dev \
                        beignet-opencl-icd nvidia-driver nvidia-opencl-icd

# add edge tpu delegate support
wget -q -O - https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/coral-edgetpu.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/coral-edgetpu.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list
sudo apt update
sudo apt install libedgetpu-dev libedgetpu1-std
sudo systemctl restart udev

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
