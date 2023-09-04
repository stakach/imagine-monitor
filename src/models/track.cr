require "uuid"
require "./matrix"

class Track
  property state : Matrix
  property age : Int32
  property uuid : UUID
  property lost_age : Int32

  def initialize(x_mid, y_mid, width, height)
    # Initial state: [x_mid, y_mid, width, height, dx, dy, dwidth, dheight]
    @state = Matrix.column_vector([x_mid.to_f, y_mid.to_f, width.to_f, height.to_f, 0.0, 0.0, 0.0, 0.0])
    @age = 0
    @uuid = UUID.random
    @lost_age = 0
  end

  def predict
    # Simplified prediction assuming constant velocity model
    transition_data = Array.new(8) { Array.new(8, 0.0) }
    (0...8).each do |i|
      transition_data[i][i] = 1.0
      transition_data[i][i - 4] = 1.0 if i >= 4
    end
    transition_matrix = Matrix.new(transition_data)

    @state = transition_matrix * @state
  end

  def update(detection)
    x_mid = (detection.left + detection.right) / 2
    y_mid = (detection.top + detection.bottom) / 2
    width = detection.right - detection.left
    height = detection.bottom - detection.top

    @state[0, 0] = x_mid.to_f
    @state[1, 0] = y_mid.to_f
    @state[2, 0] = width.to_f
    @state[3, 0] = height.to_f

    @age += 1
    @lost_age = 0
  end
end
