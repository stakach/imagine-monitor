require "imagine/models/example_object_detection"

# outputs the video stream and detections via websockets
class Monitor < Application
  base "/video"

  MULTICAST_ADDRESS = ENV["MULTICAST_ADDRESS"]
  MULTICAST_PORT    = ENV["MULTICAST_PORT"].to_i
  STREAM            = StreamWebsocket.new(MULTICAST_ADDRESS, MULTICAST_PORT)
  STREAM.start_streaming if ENV["ENABLE_STREAMING"] == "true"

  @[AC::Route::WebSocket("/stream")]
  def websocket(socket)
    socket.on_close { STREAM.remove(socket) }
    STREAM.add socket
  end

  MODEL    = Imagine::Model::ExampleObjectDetection.new(Path.new ENV["MODEL_PATH"])
  DETECTOR = Detector.new(URI.new("udp", MULTICAST_ADDRESS, MULTICAST_PORT), MODEL)
  DETECTOR.start if ENV["ENABLE_DETECTOR"] == "true"

  @[AC::Route::WebSocket("/detections")]
  def websocket(socket, include_frame : Bool = false)
    DETECTOR.add socket
    socket.on_close { DETECTOR.remove socket }
  end
end
