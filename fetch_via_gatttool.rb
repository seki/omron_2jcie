class OmronSensor
  def initialize(addr = 'F6:18:A3:56:8A:25')
    @addr = addr
  end

  Tlatest_sensing_data = [
    ['sequence_number', 1],
    ['temperature', 100],
    ['relative_humidity', 100],
    ['ambient_light', 1],
    ['barometric_pressure', 1000],
    ['sound_noise', 100],
    ['eTVOC', 1],
    ['eCO2', 1]
  ]

  Tlatest_calculation_data = [
    ['sequence_number', 1],
    ['discomfort_index', 100],
    ['heat_stroke', 100],
    ['vibration_information', 1],
    ['SI_value', 10],
    ['PGA', 10],
    ['seismic_intensity', 1000],
    ['acceleration_x', 10],
    ['acceleration_y', 10],
    ['acceleration_z', 10],
  ]

  def data_to_hash(data, template)
    template.zip(data).map do |fmt, v|
      [fmt[0], v.fdiv(fmt[1])]
    end.to_h
  end

  def latest_sensing_data
    result = `sudo gatttool -b #{@addr} -t random --char-read -a 0x59`
    if /\ACharacteristic value\/descriptor\: (.*)/ =~ result
      [$1.split.join('')].pack("H*").unpack("Cssslsss")
    else
      nil
    end
  end

  def latest_calculation_data
    result = `sudo gatttool -b #{@addr} -t random --char-read -a 0x5c`
    if /\ACharacteristic value\/descriptor\: (.*)/ =~ result
      [$1.split.join('')].pack("H*").unpack("CssCSSSsss")
    else
      nil
    end
  end

  def notify_sensing_data(queue)
    cmd = "sudo gatttool -b #{@addr} -t random --char-write-req -a 0x5a -n 0100 --listen"
    begin
      io = IO.popen(cmd, 'r')
      while line = io.gets
        if /value\: (.*)/ =~ line
          it = [$1.split.join('')].pack("H*").unpack("Cssslsss")
          queue.push(data_to_hash(it, Tlatest_sensing_data))
        end
      end
      puts 'closed'
    rescue
      io.close
      puts 'rescue'
    end
  end
end

if __FILE__ == $0
  require 'pp'
  require 'thread'
  o = OmronSensor.new
=begin
  v1 = o.latest_sensing_data
  v2 = o.latest_calculation_data
  pp o.data_to_hash(v1, OmronSensor::Tlatest_sensing_data)
  pp o.data_to_hash(v2, OmronSensor::Tlatest_calculation_data)
=end
  queue = Queue.new
  Thread.new {o.notify_sensing_data(queue)}
  while true
    pp queue.pop
  end
end