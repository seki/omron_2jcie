class OmronSensor
  def initialize(addr = 'F6:18:A3:56:8A:25')
    @addr = addr
  end

  Tlatest_sensing_data = [
    ['sequence_number', 1],
    ['temperature', 0.01],
    ['relative_humidity', 0.01],
    ['ambient_light', 1],
    ['barometric_pressure', 0.001],
    ['sound_noise', 0.01],
    ['eTVOC', 1],
    ['eCO2', 1]
  ]

  Tlatest_calculation_data = [
    ['sequence_number', 1],
    ['discomfort_index', 0.01],
    ['heat_stroke', 0.01],
    ['vibration_information', 1],
    ['SI_value', 0.1],
    ['PGA', 0.1],
    ['seismic_intensity', 0.001],
    ['acceleration_x', 0.1],
    ['acceleration_y', 0.1],
    ['acceleration_z', 0.1],
  ]

  def data_to_hash(data, template)
    template.zip(data).map do |fmt, v|
      [fmt[0], v * fmt[1]]
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
          queue.push(it)
        end
      end
    rescue
      io.close
    end
  end
end

if __FILE__ == $0
  require 'pp'
  require 'thread'
  o = OmronSensor.new
  v1 = o.latest_sensing_data
  v2 = o.latest_calculation_data
  pp o.data_to_hash(v1, OmronSensor::Tlatest_sensing_data)
  pp o.data_to_hash(v2, OmronSensor::Tlatest_calculation_data)
  queue = Queue.new
  Thread.new {o.notify_sensing_data(queue)}
  while true
    pp o.data_to_hash(queue.pop, OmronSensor::Tlatest_sensing_data)
  end
end