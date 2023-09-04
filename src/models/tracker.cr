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
    # Predict states for existing tracks
    @tracks.each(&.predict)

    mapped = detections.map do |detection|
      # Using IoU for association, in a real-world scenario, you'd use Hungarian algorithm
      matched_track = @tracks.empty? ? nil : @tracks.max_by { |track| iou(track.state, detection) }

      if matched_track && iou(matched_track.state, detection) > 0.5
        matched_track.update(detection)
        track = matched_track
      else
        x_mid = (detection.left + detection.right) / 2
        y_mid = (detection.top + detection.bottom) / 2
        width = detection.right - detection.left
        height = detection.bottom - detection.top

        track = Track.new(x_mid, y_mid, width, height)
        @tracks << track
      end

      MappedDetection.new(
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

    inter_area = [0, inter_right - inter_left].max * [0, inter_bottom - inter_top].max
    union_area = (track_right - track_left) * (track_bottom - track_top) + (detection.right - detection.left) * (detection.bottom - detection.top) - inter_area

    inter_area / union_area
  end
end
