require 'bundler/setup'
require 'json'
require 'socket'
require './sensortag.rb'

PUBLISH_INTERVAL = 60
LUX_THRESHOLD = 100
SOCKET_FILE = '¥0/pd_emitter_lite/device_user_0000001.sock'

log = Logger.new('logs/publish_socket.log')

def statement(ambient:, object:, humidity:, pressure:, lux:)
  {
    state: {
      desired: {
        ambient:     ambient,
        object:      object,
        humidity:    humidity,
        pressure:    pressure,
        lux:         lux,
        light_power: lux >= LUX_THRESHOLD ? 'on' : 'off'
      }
    }
  }
end

sensor_tag = SensorTag.new

begin
  sensor_tag.connect
  sensor_tag.enable_ir_temperature
  sensor_tag.enable_humidity
  sensor_tag.enable_barometer
  sensor_tag.enable_luxometer

  UNIXSocket.open(SOCKET_FILE) do |sock|
    loop do
      ambient, object = sensor_tag.read_ir_temperature_once
      _, humidity     = sensor_tag.read_humidity_once
      _, pressure     = sensor_tag.read_barometer_once
      lux             = sensor_tag.read_luxometer_once

      desired_state = statement(ambient: ambient, object: object, humidity: humidity, pressure: pressure, lux: lux).to_json
      sock.write(desired_state)
      log.info("Desired state: #{desired_state}")

      sleep PUBLISH_INTERVAL
    end
  end
rescue Interrupt => e
  puts e
ensure
  sensor_tag.disconnect
end
