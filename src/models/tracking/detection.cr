require "json"

class Tracking::Detection
  include JSON::Serializable

  getter top : Float32
  getter left : Float32
  getter bottom : Float32
  getter right : Float32
  getter classification : Int32
  getter name : String?
  getter score : Float32
  property uuid : String? = nil

  def initialize(
    @top, @left, @bottom, @right, @classification,
    @name, @score
  )
  end

  def self.from_detector(detection)
    Tracking::Detection.new(
      detection.top, detection.left,
      detection.bottom, detection.right,
      detection.classification, detection.name,
      detection.score
    )
  end
end
