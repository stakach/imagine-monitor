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
    spawn { start_detection }
  end

  def stop : Nil
    @detecting = false
    @detector.stop
  end

  protected def start_detection
    @detector.detections do |frame, detections, fps, scale_time, invoke_time, frame_counter, frame_invoked|
      sockets = @socket_lock.synchronize { @sockets.dup }

      payload = {
        # provide the frame information as the NN input is a subset
        # of the full video frame
        fps:        fps.frames_per_second,
        scale:      scale_time.total_milliseconds,
        invoke:     invoke_time.total_milliseconds,
        width:      frame.width,
        height:     frame.height,
        detections: detections,
        frame_counter: frame_counter,
        frames_scaled: frame_invoked,
      }.to_json

      # TODO:: should probably send in parallel and also detect slow clients and close them
      # or provide a simple queue of 1 and overwrite any queued data - i.e. client misses some detections
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
  ensure
    # resume detecting if the stream disconnects
    if @detecting
      sleep 2
      spawn { start_detection } if @detecting
    end
  end

  def add(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets << socket }
  end

  def remove(socket : HTTP::WebSocket)
    @socket_lock.synchronize { @sockets.delete socket }
  end
end
