class OmronSensor
  def initialize(addr = 'F6:18:A3:56:8A:25')
    @addr = addr
  end

  T_latest_sensing_data = [
    ['sequence_number', 1],
    ['temperature', 100],
    ['relative_humidity', 100],
    ['ambient_light', 1],
    ['barometric_pressure', 1000],
    ['sound_noise', 100],
    ['eTVOC', 1],
    ['eCO2', 1]
  ]

  T_latest_calculation_data = [
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

  def request_memory_index(start_index, end_index)
    data = [start_index, end_index, 0].pack("LLC").unpack('H*').first
    puts data
    `sudo gatttool -b #{@addr} -t random --char-write-req -a 0x0f -n #{data}`
    result = `sudo gatttool -b #{@addr} -t random --char-read -a 0x11`
    parse_char_read(result, "CQS")
  end

  def memory_index
    result = `sudo gatttool -b #{@addr} -t random --char-read -a 0x0d`
    latest, last = parse_char_read(result, "LL")
  end

  def time_setting
    time = [Time.now.to_i].pack('Q').unpack('H*').first
    `sudo gatttool -b #{@addr} -t random --char-write-req -a 0x22 -n #{time}`
  end

  def parse_char_read(str, format)
    if /\ACharacteristic value\/descriptor\: (.*)/ =~ str
      [$1.split.join('')].pack("H*").unpack(format)
    else
      nil
    end
  end

  def latest_sensing_data
    result = `sudo gatttool -b #{@addr} -t random --char-read -a 0x59`
    parse_char_read(result, "Cssslsss")

  end

  def latest_calculation_data
    result = `sudo gatttool -b #{@addr} -t random --char-read -a 0x5c`
    parse_char_read(result, "CssCSSSsss")
  end

  def notify_sensing_data(queue)
    cmd = "sudo gatttool -b #{@addr} -t random --char-write-req -a 0x5a -n 0100 --listen"
    begin
      io = IO.popen(cmd, 'r')
      while line = io.gets
        if /value\: (.*)/ =~ line
          it = [$1.split.join('')].pack("H*").unpack("Cssslsss")
          queue.push(data_to_hash(it, T_latest_sensing_data))
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
  o = OmronSensor.new
  latest, last = o.memory_index
  pp o.request_memory_index(last, latest)
end