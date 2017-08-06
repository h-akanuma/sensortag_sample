require 'bundler/setup'
require 'mqtt'
require 'json'
require 'open3'
require 'uri'
require 'open-uri'
require './led.rb'

BEAM_URL = 'beam.soracom.io'
TOPIC = '$aws/things/sensor_tag/shadow/update'
DELTA_TOPIC = "#{TOPIC}/delta"
SPEECH_TOPIC = '/iot/sensor_tag/voices'
SOUNDS_DIR = '/home/pi/sounds/voices'

LED_GPIO = 22

log = Logger.new('logs/subscribe.log')

def statement(ambient:, object:, humidity:, pressure:, lux:, light_power:)
  reported = {}
  reported[:ambient]     = ambient     unless ambient.nil?
  reported[:object]      = object      unless object.nil?
  reported[:humidity]    = humidity    unless humidity.nil?
  reported[:pressure]    = pressure    unless pressure.nil?
  reported[:lux]         = lux         unless lux.nil?
  reported[:light_power] = light_power unless light_power.nil?

  {
    state: {
      reported: reported
    }
  }
end

def toggle_led(led:, light_power:)
  return if light_power.nil?

  light_power == 'on' ? led.on : led.off
end

def run_speech_thread(log)
  log.info("Running speech thread.")
  Thread.new do
    begin
      MQTT::Client.connect(host: BEAM_URL) do |client|
        client.subscribe(SPEECH_TOPIC)
        log.info("Subscribed to the topic: #{SPEECH_TOPIC}")

        client.get do |topic, json|
          speech_url = JSON.parse(json)['speech_url']
          speech_uri = URI.parse(speech_url)
          speech_file = speech_uri.path.split('/').last
          speech_file_path = "#{SOUNDS_DIR}/#{speech_file}"

          unless File.exist?(speech_file_path)
            log.info("Opening URL: #{speech_url}")
            open(speech_url) do |file|
              open(speech_file_path, 'w+b') do |out|
                out.write(file.read)
              end
            end
          end

          log.info("Speaking: #{speech_file_path}")
          Open3.capture3("mpg321 #{speech_file_path}")
        end
      end
    rescue => e
      log.error(e.backtrace.join("\n"))
    end
  end
end

led = LED.new(pin: LED_GPIO)

run_speech_thread(log)

MQTT::Client.connect(host: BEAM_URL) do |client|
  initial_state = statement(ambient: 0, object: 0, humidity: 0, pressure: 0, lux: 0, light_power: 'off').to_json
  client.publish(TOPIC, initial_state)
  log.info("Published initial statement: #{initial_state}")

  client.subscribe(DELTA_TOPIC)
  log.info("Subscribed to the topic: #{DELTA_TOPIC}")

  client.get do |topic, json|
    state = JSON.parse(json)['state']
    ambient     = state['ambient']
    object      = state['object']
    humidity    = state['humidity']
    pressure    = state['pressure']
    lux         = state['lux']
    light_power = state['light_power']

    toggle_led(led: led, light_power: light_power)

    reported_state = statement(
                       ambient:     ambient,
                       object:      object,
                       humidity:    humidity,
                       pressure:    pressure,
                       lux:         lux,
                       light_power: light_power
                     ).to_json

    client.publish(TOPIC, reported_state)
    log.info("Reported state: #{reported_state}")
  end
end
