require 'bundler/setup'
require 'pi_piper'

class LED
  def initialize(pin:)
    @pin = PiPiper::Pin.new(pin: pin, direction: :out)
  end

  def on
    @pin.on
  end

  def off
    @pin.off
  end

  def flash
    loop do
      @pin.on
      sleep 1
      @pin.off
      sleep 1
    end
  end
end

if $0 == __FILE__
  led = LED.new(pin: ARGV[0].to_i)
  puts led.inspect
  led.flash
end
