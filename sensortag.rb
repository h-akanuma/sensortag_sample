require 'bundler/setup'
require './ble.rb'

class SensorTag
  DEVICE_NAME = 'CC2650'
  SCALE_LSB = 0.03125

  module UUID
    IR_TEMPERATURE_SERVICE     = 'f000aa00-0451-4000-b000-000000000000'
    HUMIDITY_SERVICE           = 'f000aa20-0451-4000-b000-000000000000'
    BAROMETER_SERVICE          = 'f000aa40-0451-4000-b000-000000000000'
    MOVEMENT_SERVICE           = 'f000aa80-0451-4000-b000-000000000000'
    LUXOMETER_SERVICE          = 'f000aa70-0451-4000-b000-000000000000'
    SIMPLE_KEYS_SERVICE        = '0000ffe0-0000-1000-8000-00805f9b34fb'
    IO_SERVICE                 = 'f000aa64-0451-4000-b000-000000000000'
    REGISTER_SERVICE           = 'f000ac00-0451-4000-b000-000000000000'
    CONNECTION_CONTROL_SERVICE = 'f000ccc0-0451-4000-b000-000000000000'
    OAT_SERVICE                = 'f000ffc0-0451-4000-b000-000000000000'

    IR_TEMPERATURE_CONFIG = 'f000aa02-0451-4000-b000-000000000000'
    IR_TEMPERATURE_DATA   = 'f000aa01-0451-4000-b000-000000000000'
    HUMIDITY_CONFIG       = 'f000aa22-0451-4000-b000-000000000000'
    HUMIDITY_DATA         = 'f000aa21-0451-4000-b000-000000000000'
    MOVEMENT_CONFIG       = 'f000aa82-0451-4000-b000-000000000000'
    MOVEMENT_DATA         = 'f000aa81-0451-4000-b000-000000000000'
    BAROMETER_CONFIG      = 'f000aa42-0451-4000-b000-000000000000'
    BAROMETER_DATA        = 'f000aa41-0451-4000-b000-000000000000'
    LUXOMETER_CONFIG      = 'f000aa72-0451-4000-b000-000000000000'
    LUXOMETER_DATA        = 'f000aa71-0451-4000-b000-000000000000'
    IO_CONFIG             = 'f000aa66-0451-4000-b000-000000000000'
    IO_DATA               = 'f000aa65-0451-4000-b000-000000000000'
  end

  def connect
    @ble = BLE.new
    @device = @ble.device_by_name(DEVICE_NAME)
    @device.connect
  end

  def enable(service, config_uuid, value = [0x01])
    characteristic = service.characteristic_by_uuid(config_uuid)
    characteristic.write(value)
  end

  def enable_ir_temperature
    service = @device.service_by_uuid(SensorTag::UUID::IR_TEMPERATURE_SERVICE)
    enable(service, SensorTag::UUID::IR_TEMPERATURE_CONFIG)
  end

  def enable_humidity
    service = @device.service_by_uuid(SensorTag::UUID::HUMIDITY_SERVICE)
    enable(service, SensorTag::UUID::HUMIDITY_CONFIG)
  end

  def enable_movement
    service = @device.service_by_uuid(SensorTag::UUID::MOVEMENT_SERVICE)
    enable(service, SensorTag::UUID::MOVEMENT_CONFIG, [0b11111111, 0b00000000])
  end

  def enable_barometer
    service = @device.service_by_uuid(SensorTag::UUID::BAROMETER_SERVICE)
    enable(service, SensorTag::UUID::BAROMETER_CONFIG)
  end

  def enable_luxometer
    service = @device.service_by_uuid(SensorTag::UUID::LUXOMETER_SERVICE)
    enable(service, SensorTag::UUID::LUXOMETER_CONFIG)
  end

  def convert_ir_temperature_value(upper_byte, lower_byte)
    (((upper_byte << 8) + lower_byte) >> 2) * SCALE_LSB
  end

  def convert_temp_value(upper_byte, lower_byte)
    temp_byte = (upper_byte << 8) + lower_byte
    (temp_byte / 65536.0) * 165 - 40
  end

  def convert_humidity_value(upper_byte, lower_byte)
    hum_byte = (upper_byte << 8) + lower_byte
    (hum_byte / 65536.0) * 100
  end

  def convert_movement_value(upper_byte, lower_byte)
      value = (upper_byte << 8) + lower_byte
      if upper_byte > 0x7f
        value = ~value + 1
      end
      (value >> 2).to_f
  end

  def convert_gyro_value(upper_byte, lower_byte)
    convert_movement_value(upper_byte, lower_byte) / 128.0
  end

  def convert_acc_value(upper_byte, lower_byte)
    convert_movement_value(upper_byte, lower_byte) / (32768 / 2)
  end

  def convert_mag_value(upper_byte, lower_byte)
    convert_movement_value(upper_byte, lower_byte) * 4912.0 / 32768.0
  end

  def convert_barometer_value(upper_byte, middle_byte, lower_byte)
    ((upper_byte << 16) + (middle_byte << 8) + lower_byte) / 100.0
  end

  def convert_luxometer_value(upper_byte, lower_byte)
    lux = (upper_byte << 8) + lower_byte

    m = lux & 0x0fff
    e = (lux & 0xf000) >> 12
    e = (e == 0) ? 1 : 2 << (e - 1)
    m * (0.01 * e)
  end

  def handle_ir_temperature_values(values)
    amb_lower_byte = values[2]
    amb_upper_byte = values[3]
    ambient = convert_ir_temperature_value(amb_upper_byte, amb_lower_byte)

    obj_lower_byte = values[0]
    obj_upper_byte = values[1]
    object = convert_ir_temperature_value(obj_upper_byte, obj_lower_byte)

    return ambient, object
  end

  def read_ir_temperature
    service = @device.service_by_uuid(SensorTag::UUID::IR_TEMPERATURE_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::IR_TEMPERATURE_DATA)
    characteristic.start_notify do |v|
      ambient, object = handle_ir_temperature_values(v)
      yield(ambient, object)
    end
  end

  def read_ir_temperature_once
    service = @device.service_by_uuid(SensorTag::UUID::IR_TEMPERATURE_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::IR_TEMPERATURE_DATA)
    v = characteristic.read
    ambient, object = handle_ir_temperature_values(v)
    return ambient, object
  end

  def handle_humidity_values(values)
    temp_lower_byte = values[0]
    temp_upper_byte = values[1]
    temp = convert_temp_value(temp_upper_byte, temp_lower_byte)

    hum_lower_byte = values[2]
    hum_upper_byte = values[3]
    hum = convert_humidity_value(hum_upper_byte, hum_lower_byte)

    return temp, hum
  end

  def read_humidity
    service = @device.service_by_uuid(SensorTag::UUID::HUMIDITY_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::HUMIDITY_DATA)
    characteristic.start_notify do |v|
      temperature, humidity = handle_humidity_values(v)
      yield(temp, hum)
    end
  end

  def read_humidity_once
    service = @device.service_by_uuid(SensorTag::UUID::HUMIDITY_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::HUMIDITY_DATA)
    v = characteristic.read
    temperature, humidity = handle_humidity_values(v)
    return temperature, humidity
  end

  def read_movement
    service = @device.service_by_uuid(SensorTag::UUID::MOVEMENT_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::MOVEMENT_DATA)
    characteristic.start_notify do |v|
      gyro_x_lower = v[0]
      gyro_x_upper = v[1]
      gyro_y_lower = v[2]
      gyro_y_upper = v[3]
      gyro_z_lower = v[4]
      gyro_z_upper = v[5]

      gyro_x = convert_gyro_value(gyro_x_upper, gyro_x_lower)
      gyro_y = convert_gyro_value(gyro_y_upper, gyro_y_lower)
      gyro_z = convert_gyro_value(gyro_z_upper, gyro_z_lower)

      acc_x_lower = v[6]
      acc_x_upper = v[7]
      acc_y_lower = v[8]
      acc_y_upper = v[9]
      acc_z_lower = v[10]
      acc_z_upper = v[11]

      acc_x = convert_acc_value(acc_x_upper, acc_x_lower)
      acc_y = convert_acc_value(acc_y_upper, acc_y_lower)
      acc_z = convert_acc_value(acc_z_upper, acc_z_lower)

      mag_x_lower = v[12]
      mag_x_upper = v[13]
      mag_y_lower = v[14]
      mag_y_upper = v[15]
      mag_z_lower = v[16]
      mag_z_upper = v[17]

      mag_x = convert_mag_value(mag_x_upper, mag_x_lower)
      mag_y = convert_mag_value(mag_y_upper, mag_y_lower)
      mag_z = convert_mag_value(mag_z_upper, mag_z_lower)

      yield(gyro_x, gyro_y, gyro_z, acc_x, acc_y, acc_z, mag_x, mag_y, mag_z)
    end
  end

  def handle_barometer_values(values)
    temp_lower  = values[0]
    temp_middle = values[1]
    temp_upper  = values[2]
    temp = convert_barometer_value(temp_upper, temp_middle, temp_lower)

    press_lower  = values[3]
    press_middle = values[4]
    press_upper  = values[5]
    press = convert_barometer_value(press_upper, press_middle, press_lower)

    return temp, press
  end

  def read_barometer
    service = @device.service_by_uuid(SensorTag::UUID::BAROMETER_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::BAROMETER_DATA)
    characteristic.start_notify do |v|
      temp, press = handle_barometer_values(v)
      yield(temp, press)
    end
  end

  def read_barometer_once
    service = @device.service_by_uuid(SensorTag::UUID::BAROMETER_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::BAROMETER_DATA)
    v = characteristic.read
    temp, press = handle_barometer_values(v)
    return temp, press
  end

  def handle_luxometer_values(values)
    lux_lower  = values[0]
    lux_upper  = values[1]
    convert_luxometer_value(lux_upper, lux_lower)
  end

  def read_luxometer
    service = @device.service_by_uuid(SensorTag::UUID::LUXOMETER_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::LUXOMETER_DATA)
    characteristic.start_notify do |v|
      lux = handle_luxometer_values(v)
      yield(lux)
    end
  end

  def read_luxometer_once
    service = @device.service_by_uuid(SensorTag::UUID::LUXOMETER_SERVICE)
    characteristic = service.characteristic_by_uuid(SensorTag::UUID::LUXOMETER_DATA)
    v = characteristic.read
    handle_luxometer_values(v)
  end

  def read_battery_level
    @device.read_battery_level do |battery_level|
      yield(battery_level)
    end
  end

  def run
    main = DBus::Main.new
    main << @ble.bus

    main.run
  end

  def disconnect
    @device.disconnect
  end
end

if $0 == __FILE__
  sensor_tag = SensorTag.new
  begin
    sensor_tag.connect

    ir_temperature_log = Logger.new('logs/ir_temperature.log')
    sensor_tag.enable_ir_temperature
    sensor_tag.read_ir_temperature do |ambient, object|
      ir_temperature_log.info("amb: #{ambient} obj: #{object}")
    end

    humidity_log = Logger.new('logs/humidity.log')
    sensor_tag.enable_humidity
    sensor_tag.read_humidity do |temp, hum|
      humidity_log.info("temp: #{temp} hum: #{hum}")
    end

    gyro_log = Logger.new('logs/gyro.log')
    acc_log = Logger.new('logs/acc.log')
    mag_log = Logger.new('logs/mag.log')
    sensor_tag.enable_movement
    sensor_tag.read_movement do |gyro_x, gyro_y, gyro_z, acc_x, acc_y, acc_z, mag_x, mag_y, mag_z|
      gyro_log.info("gyro: #{gyro_x} #{gyro_y} #{gyro_z}")
      acc_log.info("acc: #{acc_x} #{acc_y} #{acc_z}")
      mag_log.info("mag: #{mag_x} #{mag_y} #{mag_z}")
    end

    barometer_log = Logger.new('logs/barometer.log')
    sensor_tag.enable_barometer
    sensor_tag.read_barometer do |temp, press|
      barometer_log.info("temp: #{temp} press: #{press}")
    end

    lux_log = Logger.new('logs/lux.log')
    sensor_tag.enable_luxometer
    sensor_tag.read_luxometer do |lux|
      lux_log.info("lux: #{lux}")
    end

    battery_log = Logger.new('logs/battery.log')
    sensor_tag.read_battery_level do |battery_level|
      battery_log.info("battery: #{battery_level}")
    end

    sensor_tag.run
  rescue Interrupt => e
    puts e
  ensure
    sensor_tag.disconnect
  end
end
