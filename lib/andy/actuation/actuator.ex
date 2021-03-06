defmodule Andy.Actuator do
  @moduledoc "An actuator that translates intents into commands sent to motors"

  require Logger

  alias Andy.{
    Script,
    Device,
    MotorSpec,
    LEDSpec,
    SoundSpec,
    GM.PubSub,
    Intent
  }

  import Andy.Utils

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([actuator_config]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: {__MODULE__, :start_link, [actuator_config]}
    }
  end

  @doc "Start an actuator from a configuration"
  def start_link(actuator_config) do
    Logger.info("Starting #{__MODULE__} #{inspect(actuator_config.name)}")

    {:ok, pid} =
      Agent.start_link(
        fn ->
          devices =
            case actuator_config.type do
              :motor ->
                find_motors(actuator_config.specs)

              :led ->
                find_leds(actuator_config.specs)

              :sound ->
                find_sound_players(actuator_config.specs)
            end

          %{
            actuator_config: actuator_config,
            devices: devices,
            name: actuator_config.name
          }
        end,
        name: actuator_config.name
      )

    listen_to_events(pid, __MODULE__, actuator_config.name)
    {:ok, pid}
  end

  def realize_intent(
        %Intent{duration: duration} = intent,
        %{actuator_config: actuator_config} = state
      ) do
    if Intent.stale?(intent),
      do: Logger.warn("Stale #{inspect(intent)}! Age = #{Intent.age(intent)}")

    Logger.info("Realizing intent #{inspect(intent)}")

    actuator_config.activations
    |> Enum.filter(fn activation -> activation.intent == intent.about end)
    |> Enum.map(fn activation -> activation.script end)
    |> Enum.each(
      # execute activated script sequentially
      fn script_generator ->
        script = script_generator.(intent, state.devices)
        Script.execute(actuator_config.type, script)
      end
    )

    sleep_msecs = round(1000 * (duration || Intent.default_duration()))

    spawn(fn ->
      Process.sleep(sleep_msecs)
      PubSub.notify_actuated(intent)
    end)
  end

  def handle_event({:intended, %Intent{} = intent}, %{actuator_config: actuator_config} = state) do
    if intent.about in actuator_config.intents do
      realize_intent(intent, state)
    end

    state
  end

  def handle_event(_event, state) do
    # 		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### Private

  defp find_motors(motor_specs) do
    all_motors = platform_dispatch(:motors)

    found =
      Enum.reduce(
        motor_specs,
        %{},
        fn motor_spec, acc ->
          motor =
            Enum.find(
              all_motors,
              &MotorSpec.matches?(motor_spec, &1)
            )

          if motor == nil do
            Logger.warn(
              "Motor not found matching #{inspect(motor_spec)} in #{inspect(all_motors)}"
            )

            acc
          else
            Map.put(acc, motor_spec.name, update_props(motor, motor_spec.props))
          end
        end
      )

    found
  end

  defp find_leds(led_specs) do
    all_leds = platform_dispatch(:lights)

    found =
      Enum.reduce(
        led_specs,
        %{},
        fn led_spec, acc ->
          led =
            Enum.find(
              all_leds,
              &LEDSpec.matches?(led_spec, &1)
            )

          if led == nil do
            Logger.warn("LED not found matching #{inspect(led_spec)} in #{inspect(all_leds)}")
            acc
          else
            Map.put(acc, led_spec.name, update_props(led, led_spec.props))
          end
        end
      )

    found
  end

  defp find_sound_players(sound_specs) do
    all_sound_players = platform_dispatch(:sound_players)

    found =
      Enum.reduce(
        sound_specs,
        %{},
        fn sound_spec, acc ->
          sound_player =
            Enum.find(
              all_sound_players,
              &SoundSpec.matches?(sound_spec, &1)
            )

          if sound_player == nil do
            Logger.warn(
              "Sound player not found matching #{inspect(sound_spec)} in #{
                inspect(all_sound_players)
              }"
            )

            acc
          else
            Map.put(acc, sound_spec.name, update_props(sound_player, sound_spec.props))
          end
        end
      )

    found
  end

  defp update_props(device, props) do
    Enum.reduce(
      Map.keys(props),
      device,
      fn key, dev ->
        %Device{dev | props: Map.put(dev.props, key, Map.get(props, key, nil))}
      end
    )
  end
end
