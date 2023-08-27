class CaptureReplay
  def initialize(@location : Path, address : String, port : Int)
    @multicast_address = Socket::IPAddress.new(address, port)
    @dir = Dir.new(@location)
  end

  def configure_ram_drive
    # mkdir /mnt/ramdisk
    # mount -t tmpfs -o size=512M tmpfs /mnt/ramdisk
  end

  def capture_video
    # ffmpeg -i udp://<MULTICAST_IP>:<PORT>?overrun_nonfatal=1 -c copy -map 0 -f segment -segment_format_options break_non_keyframes=1 -reset_timestamps 1 -strftime 1 "/mnt/ramdisk/output_%Y%m%d%H%M%S.ts"
    spawn { cleanup_old_files }
  end

  def save_replay(period : Time::Span)
    half_time = period / 2
    time = half_time.ago
    sleep half_time
    files = @dir.entries.select do |file|
      File.info(file).modification_time > expired_time
    end

    # TODO:: save and merge the files to a location
  end

  def cleanup_old_files : Nil
    loop do
      sleep 11.seconds
      expired_time = 60.seconds.ago

      @dir.entries.each do |file|
        next if {".", ".."}.includes?(file)
        file = File.join(@location, file)
        File.delete(file) if File.info(file).modification_time < expired_time
      end
    end
  end
end
