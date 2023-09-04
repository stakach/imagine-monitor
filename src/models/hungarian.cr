module Hungarian
  # each integer in the result array represents the column index
  # (or the assigned track index in our context)
  # for a given row (or detection in our context).
  #
  # So, if the result is [1, 0, 2], this means:
  # * Detection 0 is assigned to track 1.
  # * Detection 1 is assigned to track 0.
  # * Detection 2 is assigned to track 2.
  # If a detection isn't assigned to any track, it will be outside the bounds of the track list.
  def self.solve(cost_matrix : Array(Array(Float64))) : Array(Int32)
    if cost_matrix.empty?
      return [] of Int32
    end

    n, m = cost_matrix.size, cost_matrix.first.size
    u, v = Array(Float64).new(n, 0.0), Array(Float64).new(m, 0.0)
    p, way = Array(Int32).new(m, 0), Array(Int32).new(m, 0)

    (0...n).each do |i|
      p.fill(0)
      assigned = Array(Int32).new(m, 0)
      minv = Array(Float64).new(m, Float64::INFINITY)
      j0 = 0

      while true
        j1 = -1
        i0 = p[j0]
        delta = Float64::INFINITY

        (0...m).each do |j|
          next if assigned[j] != 0

          cur = cost_matrix[i0][j] - u[i0] - v[j]
          if cur < minv[j]
            minv[j] = cur
            way[j] = j0
          end

          if minv[j] < delta
            delta = minv[j]
            j1 = j
          end
        end

        (0..j0).each do |j|
          if assigned[j] == 0
            minv[j] += delta
          else
            u[p[j]] += delta
            v[j] -= delta
          end
        end

        j0 = j1
        break if way[j0] == 0
      end

      while true
        j1 = way[j0]
        p[j0] = p[j1]
        j0 = j1
        break if j0 == 0
      end
      p[j0] = i
    end

    p[1..-1]
  end
end
