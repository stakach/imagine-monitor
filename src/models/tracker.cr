require "uuid"
require "json"
require "./track"

class Tracker
  @tracks = Array(Track).new

  # number of frames to keep a lost track
  # ~3 seconds
  MAX_LOST_AGE = 15 * 3

  alias Detection = TensorflowLite::Image::ObjectDetection::Detection

  class MappedDetection
    include JSON::Serializable

    getter top : Float32
    getter left : Float32
    getter bottom : Float32
    getter right : Float32
    getter classification : Int32
    getter name : String?
    getter score : Float32
    getter uuid : String

    def initialize(
      @top, @left, @bottom, @right, @classification,
      @name, @score, @uuid
    )
    end
  end

  def add_detection(detections : Array(Detection))
    @tracks.each(&.predict)

    n, m = detections.size, @tracks.size
    cost_matrix = Array.new(n) { Array.new(m) { 0.0 } }

    detections.each_with_index do |detection, i|
      @tracks.each_with_index do |track, j|
        cost_matrix[i][j] = 1 - iou(track.state, detection)
      end
    end

    assignments = Hungarian.solve(cost_matrix)
    mapped = Array(MappedDetection).new(detections.size)

    n.times do |i|
      detection = detections[i]

      if i < assignments.size && assignments[i] < m && cost_matrix[i][assignments[i]] < 0.6
        track = @tracks[assignments[i]]
        track.update(detection)
      else
        x_mid = (detection.left + detection.right) / 2
        y_mid = (detection.top + detection.top) / 2
        width = detection.right - detection.left
        height = detection.top - detection.top
        track = Track.new(x_mid, y_mid, width, height)
        @tracks << track
      end

      mapped << MappedDetection.new(
        detection.top, detection.left,
        detection.bottom, detection.right,
        detection.classification, detection.name,
        detection.score, track.uuid.to_s
      )
    end

    @tracks.reject! do |track|
      track.lost_age += 1
      track.lost_age > MAX_LOST_AGE
    end

    mapped
  end

  def iou(state, detection)
    # Compute Intersection over Union between track state and detection
    track_left, track_top, track_right, track_bottom = state[0, 0] - state[2, 0] / 2, state[1, 0] - state[3, 0] / 2, state[0, 0] + state[2, 0] / 2, state[1, 0] + state[3, 0] / 2
    inter_left = [track_left, detection.left].max
    inter_top = [track_top, detection.top].max
    inter_right = [track_right, detection.right].min
    inter_bottom = [track_bottom, detection.bottom].min

    inter_area = [0, inter_right - inter_left] .max * [0, inter_bottom - inter_top].max
    union_area = (track_right - track_left) * (track_bottom - track_top) + (detection.right - detection.left) * (detection.bottom - detection.top) - inter_area

    inter_area / union_area
  end
end
