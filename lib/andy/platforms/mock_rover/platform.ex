defmodule Andy.MockRover.Platform do
  @moduledoc "The mock ROVER platform"

  @behaviour Andy.PlatformBehaviour

  alias Andy.MockRover.{
    TouchSensor,
    ColorSensor,
    InfraredSensor,
    IRSeekerSensor,
    UltrasonicSensor,
    GyroSensor,
    Tachomotor,
    LED
  }

  alias Andy.{Device, SoundPlayer}
  require Logger

  ### PlatformBehaviour

  def start() do
    Logger.info("Platform mock_rover started")
  end

  def ready?() do
    true
  end

  def ports_config() do
    []
  end

  def display(words) do
    Logger.info("DISPLAYING: #{words}")
  end

  def actuation_logic() do
    # Use Rover's actuation
    Andy.Rover.Actuation.actuator_configs()
  end

  def device_mode(_device_type) do
    "mock"
  end

  def device_code(device_type) do
    case device_type do
      :infrared -> "mock-ir"
      :ir_seeker -> "mock-seek"
      :touch -> "mock-touch"
      :gyro -> "mock-gyro"
      :color -> "mock-color"
      :ultrasonic -> "mock-us"
      :large -> "mock-l-motor"
      :medium -> "mock-m-motor"
    end
  end

  def device_manager(_type) do
    # itself for all mock devices
    __MODULE__
  end

  def sensors() do
    [
      TouchSensor.new(),
      ColorSensor.new(),
      InfraredSensor.new(),
      IRSeekerSensor.new(),
      UltrasonicSensor.new(),
      GyroSensor.new()
    ]
  end

  def motors() do
    [
      Tachomotor.new(:large, "outA"),
      Tachomotor.new(:large, "outB"),
      Tachomotor.new(:medium, "outC")
    ]
  end

  def sound_players() do
    [SoundPlayer.new()]
  end

  def lights() do
    [
      LED.new(:blue, :left)
    ]
  end

  def shutdown() do
    Logger.info("Shutting down")
    Process.sleep(3000)
    Application.stop(:andy)
  end

  def voice() do
    "en-sc"
  end

  def sensor_read_sense(%Device{mock: true} = device, sense) do
    apply(device.mod, :read, [device, sense])
  end

  def motor_read_sense(%Device{mock: true} = device, sense) do
    apply(device.mod, :read, [device, sense])
  end

  def sensor_sensitivity(%Device{mock: true} = device, sense) do
    apply(device.mod, :sensitivity, [device, sense])
  end

  def motor_sensitivity(%Device{mock: true} = device, sense) do
    apply(device.mod, :sensitivity, [device, sense])
  end

  def senses_for_id_channel(channel) do
    [{:beacon_heading, channel}, {:beacon_distance, channel}, {:beacon_on, channel}]
  end

  def execute_command(%Device{mock: true} = device, command, params) do
    apply(device.mod, command, [device | params])
  end

end
