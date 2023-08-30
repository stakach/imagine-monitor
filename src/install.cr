#!/usr/bin/env crystal

require "colorize"
require "file"

# Install and update required packages
def install_packages
  puts "\n → Updating package lists...".colorize(:blue)
  `apt-get update`

  puts "\n → Installing required packages...".colorize(:blue)
  `apt-get install -y build-essential cmake make v4l-utils v4l2loopback-dkms ffmpeg libswscale-dev usbutils`
end

# Check if the ramdisk is configured to be mounted at startup
def ramdisk_configured?
  fstab_content = File.read("/etc/fstab")
  fstab_content.includes?("/mnt/ramdisk")
end

# Ensure ramdisk is configured to mount at startup
def ensure_ramdisk_config
  unless ramdisk_configured?
    `mkdir -p /mnt/ramdisk`
    File.open("/etc/fstab", "a") do |file|
      file.puts "tmpfs       /mnt/ramdisk   tmpfs   size=512M   0  0"
    end
    `mount -t tmpfs -o size=512M tmpfs /mnt/ramdisk`
    puts "\n → Configured ramdisk to mount at startup.".colorize(:blue)
  else
    puts "\n ✓ Ramdisk already configured to mount at startup.".colorize(:green)
  end
end

LOOPBACK_CONFIG = "/etc/modprobe.d/v4l2loopback.conf"
LOOPBACK_MODULE = "/etc/modules-load.d/v4l2loopback.conf"

# Check if loopback device is configured to run at startup
def loopback_configured?
  return false unless File.exists? LOOPBACK_CONFIG
  modprobe_content = File.read(LOOPBACK_CONFIG)
  modprobe_content.includes?("options v4l2loopback")
end

# Ensure loopback device is configured to run at startup with 2 devices
def ensure_loopback_config
  unless loopback_configured?
    File.open(LOOPBACK_CONFIG, "w") do |file|
      file.puts "options v4l2loopback devices=2"
    end
    # Ensuring module is loaded at startup
    File.open(LOOPBACK_MODULE, "w") do |file|
      file.puts "v4l2loopback"
    end
    `modprobe v4l2loopback devices=2`
    puts "\n → Configured v4l2loopback to load at startup.".colorize(:blue)
  else
    puts "\n ✓ v4l2loopback already configured to load at startup.".colorize(:green)
  end
end

install_packages
ensure_ramdisk_config
ensure_loopback_config
