require "http"
require "socket"
require "imagine"

class Detector
  Log = ::App::Log.for("detector")

  def initialize(address : URI, model : Imagine::ModelAdaptor)
    @detector = Imagine::Detector.new(address, model)
  end

  @detector : Imagine::Detector
  @sockets : Array(HTTP::WebSocket) = [] of HTTP::WebSocket
  @socket_lock : Mutex = Mutex.new
  @detecting : Bool = false

  def start : Nil
    return if @detector.processing?
    spawn { start_detection }
  end

  def stop : Nil
    @detector.stop
  end

  protected def start_detection
    @detector.detections do |_frame, detections|
      sockets = @socket_lock.synchronize { @sockets.dup }

      payload = {
        detections: detections,
      }.to_json

      # TODO:: should probably send in parallel and also detect slow clients and close them
      # not high priority
      sockets.each do |socket|
        begin
          # TODO:: provide the frame as a JPEG for those connections that would like it
          socket.send(payload)
        rescue error
          # the close callback should remove the socket
          Log.info(exception: error) { "socket send failed" }
          socket.close
        end
      end
    end
  end

  def add(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets << socket }
  end

  def remove(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets.delete socket }
  end
end
