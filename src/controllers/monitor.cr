require "socket"

# outputs the video stream and detections via websockets
class Monitor < Application
  base "/video"

  MULTICAST_ADDRESS = ENV["MULTICAST_ADDRESS"]
  MULTICAST_PORT    = ENV["MULTICAST_PORT"].to_i
  STREAM            = StreamWebsocket.new(MULTICAST_ADDRESS, MULTICAST_PORT)
  ENABLE_DETECTOR   = ENV["ENABLE_DETECTOR"]? == "true"
  ENABLE_STREAMING  = ENV["ENABLE_STREAMING"]? == "true"
  ENABLE_EDGETPU    = ENV["ENABLE_EDGETPU"]? == "true"

  @[AC::Route::WebSocket("/stream")]
  def stream(socket)
    socket.on_close { STREAM.remove(socket) }
    STREAM.add socket
  end

  MODEL_LOC = ENV["MODEL_PATH"]? ? Path.new(ENV["MODEL_PATH"]) : URI.parse(ENV["MODEL_URI"])
  MODEL_LABELS = ENV["LABELS_URI"]? ? URI.parse(ENV["LABELS_URI"]) : nil
  MODEL    = Imagine::Model::TFLiteImage.new(MODEL_LOC, labels: MODEL_LABELS, enable_tpu: ENABLE_EDGETPU)
  DETECTOR = Detector.new(URI.new("udp", MULTICAST_ADDRESS, MULTICAST_PORT), MODEL)

  @[AC::Route::WebSocket("/detections")]
  def detect(socket, include_frame : Bool = false)
    DETECTOR.add socket
    socket.on_close { DETECTOR.remove socket }
  end
end

# streaming and object detection are split between multiple processes
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

if Monitor::ENABLE_DETECTOR
  puts " > Object detection enabled..."
  Monitor::DETECTOR.start
end
