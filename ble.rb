require 'bundler/setup'
require 'dbus'

class BLE
  attr_reader :bus

  SERVICE_NAME = 'org.bluez'
  SERVICE_PATH = '/org/bluez'
  ADAPTER      = 'hci0'

  DEVICE_IF          = 'org.bluez.Device1'
  SERVICE_IF         = 'org.bluez.GattService1'
  CHARACTERISTIC_IF  = 'org.bluez.GattCharacteristic1'
  DBUS_PROPERTIES_IF = 'org.freedesktop.DBus.Properties'

  SERVICE_RESOLVED_PROPERTY = 'ServicesResolved'
  UUID_PROPERTY             = 'UUID'

  PROPERTIES_CHANGED_SIGNAL = 'PropertiesChanged'

  SERVICE_RESOLVE_CHECK_INTERVAL = 0.1
  DISCOVERY_WAITING_SECOND       = 10

  module UUID
    GENERIC_ATTRIBUTE_SERVICE  = '00001801-0000-1000-8000-00805f9b34fb'
    DEVICE_INFORMATION_SERVICE = '0000180a-0000-1000-8000-00805f9b34fb'
    BATTERY_SERVICE            = '0000180f-0000-1000-8000-00805f9b34fb'

    BATTERY_DATA = '00002a19-0000-1000-8000-00805f9b34fb'
  end

  class Device
    attr_reader :bluez, :name, :address

    def initialize(bluez, bluez_device, name, address)
      @bluez        = bluez
      @bluez_device = bluez_device
      @name         = name
      @address      = address
    end

    def connect
      @bluez_device.introspect
      @bluez_device.Connect
      @bluez_device.introspect

      while !properties[SERVICE_RESOLVED_PROPERTY] do
        sleep(SERVICE_RESOLVE_CHECK_INTERVAL)
      end
    end

    def disconnect
      @bluez_device.Disconnect
    end

    def properties
      @bluez_device.introspect
      @bluez_device.GetAll(DEVICE_IF).first
    end

    def services
      services = []
      @bluez_device.subnodes.each do |node|
        service = @bluez.object("#{@bluez_device.path}/#{node}")
        service.introspect
        properties = service.GetAll(SERVICE_IF).first
        services << Service.new(@bluez, service, properties[UUID_PROPERTY])
      end

      services
    end

    def service_by_uuid(uuid)
      services.each do |service|
        return service if service.uuid == uuid
      end

      raise 'Service not found.'
    end

    def read_battery_level
      service = service_by_uuid(BLE::UUID::BATTERY_SERVICE)
      characteristic = service.characteristic_by_uuid(BLE::UUID::BATTERY_DATA)
      yield(characteristic.read.first)
      characteristic.start_notify do |v|
        yield(v.first)
      end
    end
  end

  class Service
    attr_reader :uuid

    def initialize(bluez, bluez_service, uuid)
      @bluez         = bluez
      @bluez_service = bluez_service
      @uuid          = uuid
    end

    def properties
      @bluez_service.introspect
      @bluez_service.GetAll(SERVICE_IF).first
    end

    def characteristics
      characteristics = []
      @bluez_service.subnodes.each do |node|
        characteristic = @bluez.object("#{@bluez_service.path}/#{node}")
        characteristic.introspect
        properties = characteristic.GetAll(CHARACTERISTIC_IF).first
        characteristics << Characteristic.new(characteristic, properties[UUID_PROPERTY])
      end

      characteristics
    end

    def characteristic_by_uuid(uuid)
      characteristics.each do |characteristic|
        return characteristic if characteristic.uuid == uuid
      end

      raise 'Characteristic not found.'
    end
  end

  class Characteristic
    attr_reader :uuid

    def initialize(bluez_characteristic, uuid)
      @bluez_characteristic = bluez_characteristic
      @uuid = uuid
    end

    def properties
      @bluez_characteristic.introspect
      @bluez_characteristic.GetAll(CHARACTERISTIC_IF).first
    end

    def start_notify
      @bluez_characteristic.StartNotify
      @bluez_characteristic.default_iface = DBUS_PROPERTIES_IF
      @bluez_characteristic.on_signal(PROPERTIES_CHANGED_SIGNAL) do |_, v|
        yield(v['Value'])
      end
    end

    def write(value)
      @bluez_characteristic.WriteValue(value, {})
    end

    def read
      @bluez_characteristic.ReadValue({}).first
    end

    def inspect
      @bluez_characteristic.inspect
    end
  end

  def initialize
    @bus = DBus::system_bus
    @bluez = @bus.service(SERVICE_NAME)

    @adapter = @bluez.object("#{SERVICE_PATH}/#{ADAPTER}")
    @adapter.introspect
  end

  def devices
    @adapter.StartDiscovery
    sleep(DISCOVERY_WAITING_SECOND)

    devices = []
    @adapter.introspect
    @adapter.subnodes.each do |node|
      device = @bluez.object("#{SERVICE_PATH}/#{ADAPTER}/#{node}")
      device.introspect

      next unless device.respond_to?(:GetAll)

      properties = device.GetAll(DEVICE_IF).first
      name    = properties['Name']
      address = properties['Address']
      rssi    = properties['RSSI']

      next if name.nil? || rssi.nil?

      devices << Device.new(@bluez, device, name, address)
    end

    @adapter.StopDiscovery
    devices
  end

  def device_by_name(name)
    devices.each do |device|
      return device if device.name.downcase.include?(name.downcase)
    end

    raise 'No devices found.'
  end
end
