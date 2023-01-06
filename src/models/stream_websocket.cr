require "http"
require "socket"

class StreamWebsocket
  Log = ::App::Log.for("stream")

  def initialize(address : String, port : Int)
    @multicast_address = Socket::IPAddress.new(address, port)
  end

  def initialize(@multicast_address)
  end

  getter multicast_address : Socket::IPAddress
  getter? closed : Bool = true
  @sockets : Array(HTTP::WebSocket) = [] of HTTP::WebSocket
  @socket_lock : Mutex = Mutex.new

  def start_streaming : Nil
    return unless @closed
    @closed = false
    spawn { start_stream }
  end

  protected def start_stream
    io = UDPSocket.new
    io.read_timeout = 2.seconds
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
    if !closed?
      sleep 1
      spawn { start_stream }
    end
  end

  def close
    @closed = true
  end

  def add(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets << socket }
  end

  def remove(socket : HTTP::WebSocket)
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
        # the close callback should remove the socket
        Log.info(exception: error) { "socket send failed" }
        socket.close
      end
    end
  end
end
