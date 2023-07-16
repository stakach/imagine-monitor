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
    @detecting = true
    start_detection
  end

  def stop : Nil
    @detecting = false
    @detector.stop
  end

  protected def start_detection
    @detector.detections do |frame, detections, fps, invoke_time|
      sockets = @socket_lock.synchronize { @sockets.dup }

      payload = {
        # provide the frame information as the NN input is a subset
        # of the full video frame
        fps:        fps.frames_per_second,
        invoke:     invoke_time.total_milliseconds,
        width:      frame.width,
        height:     frame.height,
        detections: detections,
      }.to_json

      # send in parallel
      # TODO:: use a fiber pool so we're not spawning constantly here
      sockets.each do |socket|
        perform_send(socket, payload)
      end
      Fiber.yield
    end
  end

  protected def perform_send(socket, payload)
    spawn do
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

  def add(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets << socket }
  end

  def remove(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets.delete socket }
  end
end
