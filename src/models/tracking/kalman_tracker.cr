require "uuid"

class Tracking::KalmanTracker
  getter id : String
  getter kalman_filter : KalmanFilter
  property lost_counter : Int32 = 0

  def initialize(detection)
    @id = UUID.random.to_s
    detection.uuid = @id
    @kalman_filter = KalmanFilter.new(detection)
  end

  def predict(delta_t : Float64)
    @kalman_filter.predict(delta_t)
  end

  def update(detection)
    detection.uuid = id
    @kalman_filter.update(detection)
  end
end
