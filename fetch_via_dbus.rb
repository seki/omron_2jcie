require 'dbus'
require 'pp'

module MyBLE
  SERVICE_PATH = '/org/bluez'
  ADAPTER      = 'hci0'
  
  DEVICE_IF         = 'org.bluez.Device1'
  SERVICE_IF        = 'org.bluez.GattService1'
  CHARACTERISTIC_IF = 'org.bluez.GattCharacteristic1'
  PROPERTIES_IF     = 'org.freedesktop.DBus.Properties'
  
  Bus = DBus::SystemBus.instance
  Bluez = Bus.service('org.bluez')
  Adapter = Bluez.object("#{SERVICE_PATH}/#{ADAPTER}")

  module_function
  def discovery(waiting=10)
    Adapter.introspect
    puts 'Discoverying Nodes...'
    Adapter.StartDiscovery
    sleep(waiting)

    Adapter.subnodes.each do |node|
      device = Bluez.object("#{SERVICE_PATH}/#{ADAPTER}/#{node}")
      device.introspect
      properties = device.GetAll(DEVICE_IF)[0]

      yield(node, properties)
    end
  ensure
    Adapter.StopDiscovery
  end

  def connect(node, prop)
    puts "Connecting to the device: #{prop['Address']} #{prop['Name']} RSSI:#{prop['RSSI']}" if prop
    begin
      device = Bluez.object("#{SERVICE_PATH}/#{ADAPTER}/#{node}")
      device.introspect
      device.Connect
      puts 'Connected. Resolving Services...'
      device.introspect

      prop = device.GetAll(DEVICE_IF)[0]
      while ! prop['ServicesResolved'] do
        puts '.'
        sleep(0.5)
        device.introspect
        prop = device.GetAll(DEVICE_IF)[0]
      end
      puts 'Resolved.'

      return device
    rescue => e
      puts e
    end    
  end

  def services(device)
    nodes = device.subnodes
    nodes.each do |node|
      service = Bluez.object("#{device.path}/#{node}")
      service.introspect
    
      properties = service.GetAll(SERVICE_IF)[0]

      yield([service, properties])
    end
  end

  def chars(service)
    nodes = service.subnodes
    nodes.each do |node|
      char = Bluez.object("#{service.path}/#{node}")
      char.introspect
    
      properties = char.GetAll(CHARACTERISTIC_IF)[0]

      yield([char, properties])
    end
  end

  def read_value(char)
    # pp char.GetAll(CHARACTERISTIC_IF)
    char.ReadValue([])
  end
end

class MyOmron
  def initialize(device)
    @uuid_to_char = {}
    @using = [
      uuid(0x5000),
      uuid(0x5010),
      uuid(0x5110),
      uuid(0x5200)
    ]
    prepare_characteristic(device)
  end

  def uuid(short)
    "ab70%04x-0a3a-11e8-ba89-0ed5f89f718b" % short
  end

  def prepare_characteristic(dev)
    MyBLE::services(dev) do |service, prop|
      next unless using_service?(prop['UUID'])
      MyBLE::chars(service) do |char, prop|
        @uuid_to_char[prop['UUID']] = char
      end
    end
  end

  def using_service?(uuid)
    @using.include?(uuid)
  end

  def set_LED_normal(ary)
    char = @uuid_to_char[uuid(0x5111)]
    char.WriteValue(ary, {})
  end

  def read_latest_sensing
    char = @uuid_to_char[uuid(0x5012)]
    char.ReadValue([])[0]
  end

  def read_memory_index
    char = @uuid_to_char[uuid(0x5004)]
    char.ReadValue([])[0].pack('C*').unpack('LL')
  end

  def read_time_counter
    @uuid_to_char[uuid(0x5201)].ReadValue([])[0]
  end

  def read_time_setting
    @uuid_to_char[uuid(0x5202)].ReadValue([])[0]
  end

  def write_time_setting
    char = @uuid_to_char[uuid(0x5202)]
    char.WriteValue([Time.now.to_i].pack('Q').unpack('C*'), {})
  end

  def read_memory_stroage_interval
    @uuid_to_char[uuid(0x5203)].ReadValue([])[0]
  end

  def write_memory_stroage_interval(sec)
    char = @uuid_to_char[uuid(0x5203)]
    char.WriteValue([sec].pack('S').unpack('C*'), {})
  end

  def request_memory_index(from, to, type)
    it = [from, to, type].pack('LLC').unpack('C*')
    char = @uuid_to_char[uuid(0x5005)]
    char.WriteValue(it, {})
  end

  def notify_memory_sensing_data(queue)
    char = @uuid_to_char[uuid(0x500a)]
    char.StartNotify
    char.default_iface = MyBLE::PROPERTIES_IF
    char.on_signal('PropertiesChanged') do |_, v|
      queue.push(v)
    end
  end

  def notify_latest_sensing_data
    char = @uuid_to_char[uuid(0x5012)]
    char.StartNotify
    char.default_iface = MyBLE::PROPERTIES_IF
    char.on_signal('PropertiesChanged') do |_, v|
      yield(v)
    end
  end
end

if dev_name = ARGV.shift
  it = (['dev'] + dev_name.split(':')).join('_')
  dev = MyBLE::connect(it, nil)
else
  found = MyBLE::discovery do |node, prop|
    if prop['Name'] == 'Rbt-Sensor'
      break([node, prop]) 
    end
  end
  dev = MyBLE::connect(found[0], found[1])
end

omron = MyOmron.new(dev)

# omron.write_time_setting

to, from = omron.read_memory_index

omron.set_LED_normal([0, 0, 0, 0, 0])

pp omron.read_latest_sensing
sleep 1
pp omron.read_latest_sensing
sleep 1
pp omron.read_latest_sensing

omron.set_LED_normal([5, 0, 0, 0, 0])
pp omron.read_memory_index

pp omron.read_time_counter
pp omron.read_time_setting
pp omron.read_memory_stroage_interval

omron.request_memory_index(from, to, 0)
queue = Queue.new
omron.notify_memory_sensing_data(queue)

Thread.new(queue) do |q|
  while true
    pp q.pop['Value'].pack('C*').unpack('Lssslsss')
  end
end

omron.notify_latest_sensing_data {|v| 
  pp [:latest, v['Value'].pack('C*').unpack('Cssslsss')]
}

main = DBus::Main.new
main << MyBLE::Bus

main.run
