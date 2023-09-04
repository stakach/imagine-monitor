class Matrix
  property data : Array(Array(Float64))

  def initialize(data : Array(Array(Float64)))
    @data = data
  end

  def self.column_vector(values : Array(Float64))
    new(values.map { |v| [v] })
  end

  def [](i : Int32, j : Int32)
    @data[i][j]
  end

  def []=(i : Int32, j : Int32, value : Float64)
    @data[i][j] = value
  end

  def *(other : Matrix) : Matrix
    raise "Incompatible matrix dimensions." unless self.data.first.size == other.data.size

    result = Array.new(self.data.size) { Array.new(other.data.first.size, 0.0) }

    (0...self.data.size).each do |i|
      (0...other.data.first.size).each do |j|
        (0...self.data.first.size).each do |k|
          result[i][j] += self[i, k] * other[k, j]
        end
      end
    end

    Matrix.new(result)
  end

  def size
    @data.size
  end
end
