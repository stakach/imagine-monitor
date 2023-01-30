require "imagine/models/example_object_detection"

# outputs the video stream and detections via websockets
class Monitor < Application
  base "/video"

  MULTICAST_ADDRESS = ENV["MULTICAST_ADDRESS"]
  MULTICAST_PORT    = ENV["MULTICAST_PORT"].to_i
  STREAM            = StreamWebsocket.new(MULTICAST_ADDRESS, MULTICAST_PORT)

  @[AC::Route::WebSocket("/stream")]
  def stream(socket)
    socket.on_close { STREAM.remove(socket) }
    STREAM.add socket
  end

  MODEL    = Imagine::Model::ExampleObjectDetection.new(Path.new ENV["MODEL_PATH"])
  DETECTOR = Detector.new(URI.new("udp", MULTICAST_ADDRESS, MULTICAST_PORT), MODEL)

  @[AC::Route::WebSocket("/detections")]
  def detect(socket, include_frame : Bool = false)
    DETECTOR.add socket
    socket.on_close { DETECTOR.remove socket }
  end
end

# streaming and object detection are split between multiple processes
if ENV["ENABLE_STREAMING"]? == "true"
  puts " > Streaming enabled..."
  Monitor::STREAM.start_streaming
end

if ENV["ENABLE_DETECTOR"]? == "true"
  puts " > Object detection enabled..."
  Monitor::DETECTOR.start
end
