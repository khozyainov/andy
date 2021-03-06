defmodule Andy.Utils do
  @moduledoc "Utility functions"

  alias Andy.GM.PubSub
  require Logger

  @brickpi_port_pattern ~r/spi0.1:(.+)/

  def listen_to_events(pid, module, name \\ nil) do
    spawn(fn ->
      Agent.get(
        pid,
        fn state ->
          PubSub.register(module)
          state
        end
      )

      PubSub.notify({:listening, module, name})
    end)
  end

  def delay_cast(agent_name, function, delay \\ 10) do
    Process.sleep(delay)
    Agent.cast(agent_name, function)
  end

  def timeout() do
    10000
  end

  def max_beacon_channels() do
    Application.fetch_env!(:andy, :max_beacon_channels)
  end

  def very_fast_rps() do
    Application.fetch_env!(:andy, :very_fast_rps)
  end

  def fast_rps() do
    Application.fetch_env!(:andy, :fast_rps)
  end

  def normal_rps() do
    Application.fetch_env!(:andy, :normal_rps)
  end

  def slow_rps() do
    Application.fetch_env!(:andy, :slow_rps)
  end

  def very_slow_rps() do
    Application.fetch_env!(:andy, :very_slow_rps)
  end

  @doc "The time now in msecs"
  def now() do
    div(:os.system_time(), 1_000_000)
  end

  @doc "Supported time units"
  def units() do
    [:msecs, :secs, :mins, :hours]
  end

  @doc "Convert a duration to msecs"
  def convert_to_msecs(nil), do: nil

  def convert_to_msecs({count, unit}) do
    case unit do
      :msecs -> count
      :secs -> count * 1000
      :mins -> count * 1000 * 60
      :hours -> count * 1000 * 60 * 60
    end
  end

  def system_dispatch(fn_name, args) do
    apply(Andy.system(), fn_name, args)
  end

  def platform_dispatch(fn_name) do
    platform_dispatch(fn_name, [])
  end

  def platform_dispatch(fn_name, args) do
    apply(Andy.platform(), fn_name, args)
  end

  def profile_dispatch(fn_name) do
    profile_dispatch(fn_name, [])
  end

  def profile_dispatch(fn_name, args) do
    apply(Andy.profile(), fn_name, args)
  end

  def get_voice() do
    platform_dispatch(:voice)
  end

  def get_andy_env(variable) do
    get_andy_env(variable, nil)
  end

  def get_andy_env(variable, default_value) do
    Map.get(extract_plain_env_arguments(), variable) || System.get_env(variable) || default_value
  end

  def time_secs() do
    System.os_time()
    |> div(1_000_000_000)
  end

  def choose_one(choices) do
    [choice] = Enum.take_random(choices, 1)
    choice
  end

  def translate_port(port_name) do
    case Andy.system() do
      "brickpi" ->
        case Regex.run(@brickpi_port_pattern, port_name) do
          nil ->
            port_name

          [_, name] ->
            case name do
              "MA" -> "outA"
              "MB" -> "outB"
              "MC" -> "outC"
              "MD" -> "outD"
              "S1" -> "in1"
              "S2" -> "in2"
              "S3" -> "in3"
              "S4" -> "in4"
            end
        end

      _other ->
        port_name
    end
  end

  def does_match?(values, values), do: true
  def does_match?(_, _), do: false

  ### PRIVATE

  defp extract_plain_env_arguments() do
    :init.get_plain_arguments()
    |> Enum.map(&"#{&1}")
    |> Enum.filter(&Regex.match?(~r/\w+=\w+/, &1))
    |> Enum.reduce(
      %{},
      fn arg, acc ->
        case Regex.named_captures(~r/(?<var>\w+)=(?<val>\w+)/, arg) do
          %{"var" => var, "val" => val} ->
            Map.put(acc, var, val)

          nil ->
            acc
        end
      end
    )
  end
end
