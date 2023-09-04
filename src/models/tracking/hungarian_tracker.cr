require "math"
require "./detection"
require "./*"

class Tracking::HungarianTracker
  @trackers = [] of KalmanTracker
  property last_update_time : Time? = nil

  # number of frames to keep a lost track
  # ~3 seconds
  LOST_THRESHOLD = 15 * 3

  def update(detections)
    # calculate the time between detections
    current_time = Time.local
    delta_t = if last_update = @last_update_time
      (current_time - last_update).total_seconds
    else
      0.0
    end
    @last_update_time = current_time

    # 1. Predict new positions for each tracker
    @trackers.each(&.predict(delta_t))

    puts "PREDICTION MADE"

    # 2. Compute the cost matrix
    cost_matrix = compute_cost_matrix(detections)

    puts "COST COMPUTED"

    # 3. Use the Hungarian algorithm to find the optimal assignment
    assignments = hungarian_algorithm(cost_matrix)

    puts "ASSIGNMENTS DONE"

    # 4. Update the trackers based on the assignments
    # 5. Create and delete trackers if necessary
    update_trackers(detections, assignments)
  end

  def update_trackers(detections : Array(Detection), assignments : Array(Tuple(Int32, Int32)))
    assigned_detections = [] of Int32
  
    # 1. Update existing trackers with their assignments
    assignments.each do |(track_idx, detection_idx)|
      track = @trackers[track_idx]
      detection = detections[detection_idx]
  
      # Update the Kalman filter for the track
      track.update(detection)
  
      # Reset the lost counter since we've found a match
      track.lost_counter = 0
  
      # Add the detection to the list of assigned detections
      assigned_detections << detection_idx
    end
  
    # 2. Handle lost trackers
    idx = -1
    @trackers.reject! do |track|
      idx += 1
      if !assignments.includes?(idx)
        track.lost_counter += 1
        next track.lost_counter > LOST_THRESHOLD
      end
      false
    end
  
    # 3. Handle new detections
    detections.each_with_index do |detection, index|
      unless assigned_detections.includes?(index)
        # Create a new tracker for the unassigned detection
        new_tracker = KalmanTracker.new(detection)
        @trackers << new_tracker
      end
    end

    detections
  end

  private def compute_cost_matrix(detections : Array(Detection)) : Array(Array(Float64))
    cost_matrix = Array(Array(Float64)).new
  
    @trackers.each do |track|
      # Predict the next position of the track
      predicted_x = track.kalman_filter.state[0]
      predicted_y = track.kalman_filter.state[1]
  
      row_costs = Array(Float64).new
      detections.each do |detection|
        # Compute the centroid of the detection
        detection_x = (detection.left + detection.right) / 2.0
        detection_y = (detection.top + detection.bottom) / 2.0
        
        # Compute the Euclidean distance between the predicted state and the detection
        distance = Math.sqrt((predicted_x - detection_x.to_f64)**2 + (predicted_y - detection_y.to_f64)**2)
        row_costs << distance
      end
  
      cost_matrix << row_costs
    end
  
    cost_matrix
  end

  MAX_ITERATIONS = 100

  # provide the optimal assignments in the form of an array of tuples,
  # where each tuple (i, j) indicates that the ith tracked object is
  # optimally assigned to the jth detection.
  def hungarian_algorithm(cost_matrix : Array(Array(Float64)))
    row_reduction(cost_matrix)
    column_reduction(cost_matrix)
  
    covered_rows, covered_columns = cover_zeros(cost_matrix)
    
    iteration = 0
    while !is_optimal?(covered_rows, covered_columns)
      adjust_matrix(cost_matrix, covered_rows, covered_columns)
      covered_rows, covered_columns = cover_zeros(cost_matrix)

      iteration += 1
      if iteration > MAX_ITERATIONS
        puts "Warning: Exceeded max iterations! Breaking out of loop."
        break
      end
    end
    
    # At this point, the optimal assignment is possible
    # Retrieve the optimal assignments
    assignments = Array(Tuple(Int32, Int32)).new
    cost_matrix.each_with_index do |row, i|
      row.each_with_index do |value, j|
        assignments << {i, j} if value == 0
      end
    end
  
    assignments
  end  

  # 1. Subtract the Smallest Element: For each row of the matrix,
  # find the smallest element and subtract it from every element in its row.
  def row_reduction(cost_matrix)
    cost_matrix.each do |row|
      min_val = row.min
      row.map! { |v| v - min_val }
    end
  end
  
  # Then, do the same for each column.
  private def column_reduction(cost_matrix : Array(Array(Float64)))
    cost_matrix.transpose.each do |column|
      min_val = column.min
      column.map! { |val| val - min_val }
    end
    cost_matrix
  end
  
  # 2. Cover Zeros: Cover all zeros in the matrix using the minimum number of horizontal and vertical lines.
  private def cover_zeros(cost_matrix : Array(Array(Float64)))
    # Empty matrix check
    return [[] of Float64, [] of Float64] if cost_matrix.empty?

    row_covered = Array(Bool).new(cost_matrix.size, false)
    col_covered = Array(Bool).new(cost_matrix[0].size, false)
  
    cost_matrix.each_with_index do |row, i|
      row.each_with_index do |value, j|
        if value == 0.0 && !row_covered[i] && !col_covered[j]
          row_covered[i] = true
          col_covered[j] = true
        end
      end
    end
  
    [row_covered, col_covered]
  end  
  
  # 3. Test for Optimality: If there are n lines drawn (where n is the number of rows or columns of the matrix), then an optimal assignment is possible.
  def is_optimal?(covered_rows, covered_columns)
    total_covered = covered_rows.count(true) + covered_columns.count(true)
    total_covered == covered_rows.size
  end
  
  # 4. Adjust Matrix: If an optimal assignment is not yet possible,
  # find the smallest uncovered element and subtract it from all uncovered elements.
  # Add this value to the elements at the intersection of the lines. Return to step 2.
  def adjust_matrix(cost_matrix, covered_rows, covered_columns)
    min_uncovered = Float64::INFINITY
  
    cost_matrix.each_with_index do |row, i|
      row.each_with_index do |value, j|
        if !covered_rows[i] && !covered_columns[j]
          min_uncovered = value if value < min_uncovered
        end
      end
    end
    
    cost_matrix.each_with_index do |row, i|
      row.each_with_index do |value, j|
        cost_matrix[i][j] += min_uncovered if covered_rows[i] && covered_columns[j]
        cost_matrix[i][j] -= min_uncovered if !covered_rows[i] && !covered_columns[j]
      end
    end
  end
end
