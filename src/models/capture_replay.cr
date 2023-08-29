class CaptureReplay
  def initialize(@location : Path, address : String, port : Int)
    @multicast_address = Socket::IPAddress.new(address, port)
    Dir.mkdir_p @location
  end

  # so we don't destory the HD writing data all the time
  def configure_ram_drive
    output = IO::Memory.new
    status = Process.run("mount", output: output)
    raise "failed to check for existing mount" unless status.success?

    # sudo mkdir -p /mnt/ramdisk
    # sudo mount -t tmpfs -o size=512M tmpfs /mnt/ramdisk
    if !String.new(output.to_slice).includes?(@location.to_s)
      status = Process.run("mount", {"-t", "tmpfs", "-o", "size=512M", "tmpfs", @location.to_s})
      raise "failed to mount ramdisk: #{@location}" unless status.success?
    end
  end

  @capture_process : Process? = nil

  def finalize
    @capture_process.try &.terminate
  end

  def capture_video
    wait_running = Channel(Process).new
    spawn do
      filenames = File.join(@location, "output_%Y%m%d%H%M%S.ts")
      Process.run("ffmpeg", {
        "-i", "udp://#{@multicast_address.address}:#{@multicast_address.port}?overrun_nonfatal=1",
        "-c", "copy", "-copyinkf", "-an", "-map", "0", "-f",
        "segment", "-segment_time", "2",
        "-reset_timestamps", "1", "-strftime", "1", filenames.to_s,
      }, error: :inherit, output: :inherit) do |process|
        wait_running.send process
      end
    end

    # terminate ffmpeg once the spec has finished
    select
    when @capture_process = wait_running.receive
      sleep 1
    when timeout(5.seconds)
      raise "timeout waiting for video capture to start"
    end

    spawn { cleanup_old_files }
  end

  protected def cleanup_old_files : Nil
    loop do
      sleep 11.seconds
      expired_time = 180.seconds.ago

      files = Dir.entries(@location)
      puts "Checking #{files.size} files for removal"

      files.each do |file|
        begin
          next if {".", ".."}.includes?(file)
          file = File.join(@location, file)
          File.delete(file) if File.info(file).modification_time < expired_time
        rescue error
          puts "Error checking removal of #{file}\n#{error.inspect_with_backtrace}"
        end
      end
    end
  end

  def save_replay(period : Time::Span, output_file : Path)
    half_time = period / 2
    created_after = half_time.ago
    sleep half_time
    files = Dir.entries(@location).select do |file|
      next if {".", ".."}.includes?(file)
      file = File.join(@location, file)

      begin
        info = File.info(file)
        !info.size.zero? && info.modification_time >= created_after
      rescue err : File::NotFoundError
        nil
      rescue error
        puts "Error obtaining file info for #{file}\n#{error.inspect_with_backtrace}"
        nil
      end
    end

    # ensure the files are joined in the correct order
    files.map! { |file| File.join(@location, file) }.sort! do |file1, file2|
      info1 = File.info(file1)
      info2 = File.info(file2)
      info1.modification_time <=> info2.modification_time
    end

    # remove the file being currently written
    raise "no replay files found..." if files.size.zero?
    file_list = File.tempfile("replay-", ".txt") do |list|
      files.each { |file| list.puts("file '#{file}'") }
    end

    begin
      status = Process.run("ffmpeg", {
        "-f", "concat", "-safe", "0",
        "-i", file_list.path, "-c", "copy",
        output_file.to_s,
      }, error: :inherit, output: :inherit)

      raise "failed to save video replay" unless status.success?
    ensure
      file_list.delete
    end
  end
end
