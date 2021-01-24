require_relative 'omron_2jcie'

if __FILE__ == $0
  require 'pp'
  require 'thread'
  o = OmronSensor.new

  v1 = o.latest_sensing_data
  v2 = o.latest_calculation_data
  pp o.data_to_hash(v1, OmronSensor::T_latest_sensing_data)
  pp o.data_to_hash(v2, OmronSensor::T_latest_calculation_data)

  queue = Queue.new
  Thread.new {o.notify_sensing_data(queue)}
  while true
    pp queue.pop
  end
end