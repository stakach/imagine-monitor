require "socket"

# outputs the video stream and detections via websockets
class Monitor < Application
  base "/video"

  # The device details
  INPUT_DEVICE = Path[ENV["INPUT_DEVICE"]? || "/dev/video0"]
  INPUT_WIDTH  = ENV["INPUT_WIDTH"].to_i
  INPUT_HEIGHT = ENV["INPUT_HEIGHT"].to_i

  # CPU
  # MODEL_URI=https://raw.githubusercontent.com/google-coral/test_data/master/efficientdet_lite0_320_ptq.tflite
  # LABELS_URI=https://raw.githubusercontent.com/google-coral/test_data/master/coco_labels.txt
  # CORAL
  # MODEL_URI=https://raw.githubusercontent.com/google-coral/test_data/master/efficientdet_lite0_320_ptq_edgetpu.tflite
  MODEL_LOC    = ENV["MODEL_PATH"]?.presence ? Path.new(ENV["MODEL_PATH"]) : URI.parse(ENV["MODEL_URI"])
  MODEL_LABELS = ENV["LABELS_URI"]? ? URI.parse(ENV["LABELS_URI"]) : nil
  MODEL        = Imagine::Model::TFLiteImage.new(MODEL_LOC, labels: MODEL_LABELS, enable_tpu: ENABLE_EDGETPU)
  DETECTOR     = Detector.new(INPUT_DEVICE, INPUT_WIDTH, INPUT_HEIGHT, MODEL)

  # where we want the video to be streamed
  MULTICAST_ADDRESS = ENV["MULTICAST_ADDRESS"]
  MULTICAST_PORT    = ENV["MULTICAST_PORT"].to_i

  REPLAY_MOUNT_PATH = Path[ENV["REPLAY_MOUNT_PATH"]? || "/mnt/ramdisk"]

  STREAM = StreamWebsocket.new(MULTICAST_ADDRESS, MULTICAST_PORT)
  REPLAY = CaptureReplay.new(REPLAY_MOUNT_PATH, MULTICAST_ADDRESS, MULTICAST_PORT)

  ENABLE_STREAMING = ENV["ENABLE_STREAMING"]? == "true"
  ENABLE_DETECTOR  = ENV["ENABLE_DETECTOR"]? == "true"
  ENABLE_EDGETPU   = ENV["ENABLE_EDGETPU"]? == "true"
  ENABLE_REPLAY    = ENV["ENABLE_REPLAY"]? == "true"

  @[AC::Route::WebSocket("/stream")]
  def stream(socket)
    socket.on_close { STREAM.remove(socket) }
    STREAM.add socket
  end

  @[AC::Route::WebSocket("/detections")]
  def detect(socket, include_frame : Bool = false)
    DETECTOR.add socket
    socket.on_close { DETECTOR.remove socket }
  end

  @[AC::Route::GET("/replay")]
  def replay(seconds : UInt32)
    tempfile = File.tempfile(".ts")
    file_path = Path[tempfile.path]
    tempfile.close

    Monitor::REPLAY.save_replay(seconds.seconds, file_path)

    response.content_type = "video/mp2t"
    response.headers["Content-Disposition"] = %(attachment; filename="#{File.basename(file_path)}")
    @__render_called__ = true

    File.open(file_path) do |file|
      IO.copy(file, context.response)
    end
    File.delete file_path
  end
end

if Monitor::ENABLE_DETECTOR
  puts " > Object detection enabled..."
  Monitor::DETECTOR.start
end

# streaming and object detection can be split between multiple processes
if Monitor::ENABLE_STREAMING
  puts " > Streaming enabled..."
  Monitor::STREAM.start_streaming
  server = TCPServer.new(App::DEFAULT_HOST, App::DEFAULT_PORT + 1)
  spawn do
    while client = server.accept?
      begin
        Monitor::STREAM.add(client)
      rescue
        sleep 0.1
      end
    end
  end
end

if Monitor::ENABLE_REPLAY
  puts " > Replay enabled..."
  Monitor::REPLAY.configure_ram_drive
  Monitor::REPLAY.capture_video
end
