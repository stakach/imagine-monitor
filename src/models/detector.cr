require "http"
require "socket"
require "imagine"

class Detector
  Log = ::App::Log.for("detector")

  def initialize(@device : Path, width : Int32, height : Int32, model : Imagine::ModelAdaptor)
    loopback = V4L2::Video.find_loopback_device
    raise "no loopback running. run 'sudo modprobe v4l2loopback'" unless loopback
    @loopback = loopback

    video = V4L2::Video.new(@device)
    format = video.supported_formats.find! { |form| form.code == "YUYV" }
    resolution = format.frame_sizes.find! { |frame| frame.width == width && frame.height == height }
    @fps = fps = resolution.frame_rate
    video.close

    @detector = Imagine::V4L2Detector.new(loopback, fps, model)
  end

  @device : Path
  @fps : V4L2::FrameRate
  @loopback : Path
  @loopback_process : Process? = nil
  @detector : Imagine::V4L2Detector
  @sockets : Array(HTTP::WebSocket) = [] of HTTP::WebSocket
  @socket_lock : Mutex = Mutex.new
  @detecting : Bool = false

  def start : Nil
    return if @detecting
    @detecting = true

    # launch FFMPEG
    # push a video to the loopback device
    wait_running = Channel(Process).new
    spawn do
      Process.run("ffmpeg", {
        "-f", "v4l2", "-input_format", "yuyv422",
        "-video_size", "#{@fps.width}x#{@fps.height}",
        "-i", @device.to_s,
        "-c:v", "copy", "-f", "v4l2", @loopback.to_s,
      }, error: :inherit, output: :inherit) do |process|
        wait_running.send process
      end
    end

    # terminate ffmpeg once the spec has finished
    select
    when @loopback_process = wait_running.receive
      sleep 1
    when timeout(5.seconds)
      raise "timeout waiting for loopback"
    end

    start_detection
  end

  def stop : Nil
    @detecting = false
    @detector.stop
    @loopback_process.try &.terminate
  end

  def finalize
    @loopback_process.try &.terminate
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
