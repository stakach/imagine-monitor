class Tracking::KalmanFilter
  # State vector [x position, y position, x velocity, y velocity]
  getter state : Array(Float64)
  # State covariance matrix
  getter covariance : Array(Array(Float64))
  
  # Process noise covariance
  PROCESS_NOISE = [[1.0, 0.0, 0.1, 0.0], [0.0, 1.0, 0.0, 0.1], [0.1, 0.0, 1.0, 0.0], [0.0, 0.1, 0.0, 1.0]]
  # Measurement noise covariance
  MEASUREMENT_NOISE = [[0.1, 0.0], [0.0, 0.1]]
  # Identity matrix
  I = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]
  
  def initialize(detection : Detection)
    x = (detection.left + detection.right) / 2.0
    y = (detection.top + detection.bottom) / 2.0

    @state = [x.to_f64, y.to_f64, 0.0, 0.0]
    @covariance = I.clone
  end
  
  def predict(delta_t : Float64)
    # State transition matrix based on constant velocity model
    transition = [
      [1.0, 0.0, delta_t, 0.0],
      [0.0, 1.0, 0.0, delta_t],
      [0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 1.0]
    ]

    # Predicted state estimate
    @state = matrix_multiply(transition, @state)

    # Predicted estimate covariance
    @covariance = matrix_add(matrix_multiply(matrix_multiply(transition, @covariance), transpose(transition)), PROCESS_NOISE)
  end

  def update(detection : Detection)
    x = (detection.left + detection.right) / 2.0
    y = (detection.top + detection.bottom) / 2.0
    
    measurement = [x.to_f64, y.to_f64]

    # Measurement matrix
    measurement_matrix = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0]]

    # Innovation or measurement residual
    y_tilde = matrix_subtract(measurement, matrix_multiply(measurement_matrix, @state))
    
    # Innovation (or residual) covariance
    s = matrix_add(matrix_multiply(matrix_multiply(measurement_matrix, @covariance), transpose(measurement_matrix)), MEASUREMENT_NOISE)
    
    # Optimal Kalman gain
    k = matrix_multiply(matrix_multiply(@covariance, transpose(measurement_matrix)), inverse(s))
    
    # Updated (a posteriori) state estimate
    @state = matrix_add(@state, matrix_multiply(k, y_tilde))

    # Updated (a posteriori) estimate covariance
    @covariance = matrix_subtract(I, matrix_multiply(k, measurement_matrix))
  end
  
  private def matrix_multiply(a : Array(Array(Float64)), b : Array(Float64)) : Array(Float64)
    # For this simple implementation, assuming b is always a column vector
    a.map do |row|
      row.zip(b).map { |x, y| x * y }.sum
    end
  end
  
  def matrix_multiply(a : Array(Array(Float64)), b : Array(Array(Float64))) : Array(Array(Float64))
    # Ensure that the number of columns in 'a' is equal to the number of rows in 'b'.
    raise "Incompatible matrices for multiplication" unless a[0].size == b.size
    
    m, n, p = a.size, a[0].size, b[0].size
  
    # Initialize the result matrix with zeros.
    result = Array.new(m) { Array.new(p, 0.0) }
  
    # Calculate the matrix product.
    m.times do |i|
      p.times do |j|
        n.times do |k|
          result[i][j] += a[i][k] * b[k][j]
        end
      end
    end
  
    result
  end
  
  private def matrix_add(a : Array(Array(Float64)), b : Array(Array(Float64))) : Array(Array(Float64))
    a.zip(b).map { |row_a, row_b| row_a.zip(row_b).map { |x, y| x + y } }
  end

  private def matrix_add(a : Array(Array(Float64)), b : Array(Float64)) : Array(Float64)
    a.map.with_index { |row, i| row[0] + b[i] }
  end

  private def matrix_add(a : Array(Float64), b : Array(Array(Float64))) : Array(Float64)
    a.map.with_index { |value, i| value + b[i][0] }
  end

  private def matrix_add(a : Array(Float64), b : Array(Float64)) : Array(Float64)
    a.zip(b).map { |a_val, b_val| a_val + b_val }
  end  

  private def matrix_subtract(a : Array(Float64), b : Array(Float64)) : Array(Float64)
    a.zip(b).map { |a_val, b_val| a_val - b_val }
  end  

  private def matrix_subtract(a : Array(Float64), b : Array(Array(Float64))) : Array(Float64)
    a.map.with_index { |value, i| value - b[i][0] }
  end
  
  private def matrix_subtract(a : Array(Array(Float64)), b : Array(Float64)) : Array(Float64)
    a.map.with_index { |row, i| row[0] - b[i] }
  end
  
  private def matrix_subtract(a : Array(Array(Float64)), b : Array(Array(Float64))) : Array(Array(Float64))
    a.zip(b).map { |row_a, row_b| row_a.zip(row_b).map { |x, y| x - y } }
  end
  
  private def transpose(a : Array(Array(Float64))) : Array(Array(Float64))
    a.transpose
  end
  
  private def inverse(a : Array(Array(Float64))) : Array(Array(Float64))
    # For this simple implementation, we will assume a is always 2x2
    det = a[0][0] * a[1][1] - a[0][1] * a[1][0]
    [
      [a[1][1] / det, -a[0][1] / det],
      [-a[1][0] / det, a[0][0] / det]
    ]
  end
end
