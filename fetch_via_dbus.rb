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

module MyOmron
  module_function
  def uuid(short)
    "ab70%04x-0a3a-11e8-ba89-0ed5f89f718b" % short
  end

  def set_uuid_to_path(uuid, path)
    UUID_to_path[uuid] = path
  end

  def uuid_to_path(uuid)
    UUID_to_path[uuid]
  end

  MemoryDataService_UUID = uuid(0x5000)
  LatestDataService_UUID = uuid(0x5010)
  TimeSettingSservice_UUID = uuid(0x5200)

  MyService_UUID = [uuid(0x5010), uuid(0x5110)]

  LatestSensingData_UUID = uuid(0x5012)
  LatestCalculationData_UUID = uuid(0x5013)
  LEDSettingNormalState_UUID = uuid(0x5111)

  UUID_to_path = {}

  def set_LED_normal(ary)
    char = MyBLE::Bluez.object(uuid_to_path(uuid(0x5111)))
    char.WriteValue(ary, {})
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

MyBLE::services(dev) do |service, prop|
  # MyOmron::set_uuid_to_path(prop['UUID'], service.path)
  next unless MyOmron::MyService_UUID.include?(prop['UUID'])
  MyBLE::chars(service) do |char, prop|
    MyOmron::set_uuid_to_path(prop['UUID'], char.path)
  end
end

MyOmron::set_LED_normal([0, 0, 0, 0, 0])

path = MyOmron::uuid_to_path(MyOmron::LatestSensingData_UUID)
char = MyBLE::Bluez.object(path)

pp MyBLE::read_value(char)
sleep 1
pp MyBLE::read_value(char)
sleep 1
pp MyBLE::read_value(char)

MyOmron::set_LED_normal([5, 0, 0, 0, 0])
