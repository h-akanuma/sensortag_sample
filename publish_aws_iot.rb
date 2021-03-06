require 'bundler/setup'
require 'mqtt'
require 'json'
require './sensortag.rb'

AWS_IOT_URL = 'XXXXXXXXXXXXXX.iot.ap-northeast-1.amazonaws.com'
AWS_IOT_PORT = 8883
TOPIC = '$aws/things/sensor_tag/shadow/update'
PUBLISH_INTERVAL = 60
LUX_THRESHOLD = 100

log = Logger.new('logs/publish.log')

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

  MQTT::Client.connect(host: AWS_IOT_URL, port: AWS_IOT_PORT, ssl: true, cert_file: 'raspberry_pi.cert.pem', key_file: 'raspberry_pi.private.key', ca_file: 'root-CA.crt') do |client|
    loop do
      ambient, object = sensor_tag.read_ir_temperature_once
      _, humidity     = sensor_tag.read_humidity_once
      _, pressure     = sensor_tag.read_barometer_once
      lux             = sensor_tag.read_luxometer_once

      desired_state = statement(ambient: ambient, object: object, humidity: humidity, pressure: pressure, lux: lux).to_json
      client.publish(TOPIC, desired_state)
      log.info("Desired state: #{desired_state}")

      sleep PUBLISH_INTERVAL
    end
  end
rescue Interrupt => e
  puts e
ensure
  sensor_tag.disconnect
end
