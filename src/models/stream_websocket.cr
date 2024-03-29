require "http"
require "socket"

class StreamWebsocket
  Log = ::App::Log.for("stream")

  def initialize(address : String, port : Int)
    @multicast_address = Socket::IPAddress.new(address, port)
  end

  def self.new(multicast_address)
    StreamWebsocket.new(multicast_address.address, multicast_address.port)
  end

  alias Transport = HTTP::WebSocket | TCPSocket

  @streaming_process : Process? = nil
  getter multicast_address : Socket::IPAddress
  getter? closed : Bool = true
  @sockets : Array(Transport) = [] of Transport
  @socket_lock : Mutex = Mutex.new

  def start_streaming : Nil
    return unless @closed
    @closed = false

    loopback = V4L2::Video.find_loopback_device
    raise "no loopback running. run 'sudo modprobe v4l2loopback'" unless loopback

    # launch FFMPEG
    # streams the video from the loopback device
    wait_running = Channel(Process).new
    spawn do
      # ffmpeg -f v4l2 -i /dev/video4 -c:v libx264 -g 50 -f mpegts output.ts
      Process.run("ffmpeg", {
        "-f", "v4l2", "-i", loopback.to_s,
        "-c:v", "libx264", "-tune", "zerolatency", "-preset", "ultrafast",
        "-profile:v", "main", "-level:v", "3.1", "-pix_fmt", "yuv420p",
        "-g", "60",
        "-an", "-f", "mpegts", "udp://#{@multicast_address.address}:#{@multicast_address.port}?pkt_size=1316",
      }, error: :inherit, output: :inherit) do |process|
        wait_running.send process
      end
    end

    # terminate ffmpeg once the spec has finished
    select
    when @streaming_process = wait_running.receive
      sleep 1
    when timeout(5.seconds)
      raise "timeout waiting for stream to start"
    end

    spawn { start_stream }
  end

  protected def start_stream
    io = UDPSocket.new
    begin
      io.reuse_address = true
      io.reuse_port = true
      io.read_timeout = 3.seconds
      io.bind "0.0.0.0", multicast_address.port
      io.join_group(multicast_address)

      # largest packets seem to be 4096 * 15
      bytes = Bytes.new(4096 * 20)

      loop do
        break if closed? || io.closed?
        bytes_read, _client_addr = io.receive(bytes)
        break if bytes_read == 0

        publish bytes[0, bytes_read].dup
      end
    rescue error
      Log.warn(exception: error) { "error reading multicast stream" }
      io.close
      if !closed?
        sleep 1
        spawn { start_stream }
      end
    end
  end

  def close
    @closed = true
    @streaming_process.try &.terminate
  end

  def finalize
    @streaming_process.try &.terminate
  end

  def add(socket : Transport)
    @socket_lock.synchronize { @sockets << socket }
  end

  def remove(socket : Transport)
    @socket_lock.synchronize { @sockets.delete socket }
  end

  protected def publish(payload) : Nil
    sockets = @socket_lock.synchronize { @sockets.dup }

    # TODO:: should probably send in parallel and also detect slow clients and close them
    # not high priority
    sockets.each do |socket|
      begin
        socket.send payload
      rescue error
        Log.info(exception: error) { "socket send failed" }
        remove socket
        socket.close
      end
    end
  end
end
