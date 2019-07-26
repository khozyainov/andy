defmodule Andy.Memory do
  @moduledoc "The memory of percepts, intents and beliefs"

  alias Andy.{Percept, Intent, Belief, PubSub}
  import Andy.Utils
  require Logger

  @name __MODULE__
  # clear expired precepts every 10 secs
  @forget_pause 10_000
  # all intents are forgotten after 30 secs
  @intent_ttl 30_000
  # don't bother looking back beyond that
  @max_recall 30_000

  ### API

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @doc "Start the memory server"
  def start_link() do
    Logger.info("Starting #{@name}")

    {:ok, pid} =
      Agent.start_link(
        fn ->
          forgetting_pid = spawn_link(fn -> forget() end)
          Process.register(forgetting_pid, :forgetting)
          %{percepts: %{}, intents: %{}, beliefs: %{}}
        end,
        name: @name
      )

    {:ok, pid}
  end

  @doc "Remember a percept or intent"
  def store(something) do
    Agent.update(
      @name,
      fn state -> store(something, state) end
    )
  end

  @doc "Recall all matching, unexpired percepts in a time window until now, latest to oldest"
  def recall_percepts_since(about, {:past_secs, secs}) do
    Agent.get(
      @name,
      fn state ->
        percepts_since(
          as_percept_about(about),
          secs,
          state
        )
      end
    )
  end

  @doc "Recall latest unexpired, matching percept, if any"
  def recall_percepts_since(about, :now) do
    case recall_latest_percept(about) do
      nil ->
        []

      percept ->
        [percept]
    end
  end

  @doc "Recall latest matching percept"
  def recall_latest_percept(about) do
    case recall_percepts_since(as_percept_about(about), {:past_secs, @max_recall}) do
      [percept | _] ->
        percept

      [] ->
        nil
    end
  end

  @doc "Recall the value of the latest unexpired, matching percept, if any"
  def recall_value_of_latest_percept(about) do
    case recall_latest_percept(about) do
      nil ->
        nil

      percept ->
        percept.value
    end
  end

  @doc "Recall the value of the latest unexpired, matching intent, if any"
  def recall_value_of_latest_intent(intent_name) do
    case recall_latest_intent(intent_name) do
      nil ->
        nil

      intent ->
        intent.value
    end
  end

  @doc "Recall latest matching intent"
  def recall_latest_intent(intent_name) do
    case recall_intents_since(intent_name, {:past_secs, @max_recall}) do
      [intent | _] ->
        intent

      [] ->
        nil
    end
  end

  @doc "Recall the history of a named intent, within a time window until now"
  def recall_intents_since(intent_name, {:past_secs, secs}) do
    Agent.get(
      @name,
      fn state ->
        intents_since(intent_name, secs, state)
      end
    )
  end

  @doc "Recall whether a conjecture is currently believed in"
  def recall_believed?(conjecture_name) do
    Agent.get(
      @name,
      fn state ->
        believed?(conjecture_name, state)
      end
    )
  end

  ### PRIVATE

  # Forget all expired percepts every second
  defp forget() do
    :timer.sleep(@forget_pause)
    Logger.info("Forgetting old memories")
    Agent.update(@name, fn state -> forget_expired(state) end)
    forget()
  end

  # Store a percept
  defp store(%Percept{about: about} = percept, state) do
    key = about.sense
    percepts = Map.get(state.percepts, key, [])
    new_percepts = update_percepts(percept, percepts)
    PubSub.notify_percept_memorized(percept)
    %{state | percepts: Map.put(state.percepts, key, new_percepts)}
  end

  # Store an actuated intent
  defp store(%Intent{} = intent, state) do
    intents = Map.get(state.intents, intent.about, [])
    new_intents = update_intents(intent, intents)
    PubSub.notify_intent_memorized(intent)
    %{state | intents: Map.put(state.intents, intent.about, new_intents)}
  end

  # Update the current belief in a conjecture
  defp store(%Belief{} = belief, %{beliefs: beliefs} = state) do
    PubSub.notify_belief_memorized(belief)
    %{state | beliefs: Map.put(beliefs, belief.conjecture_name, belief)}
  end

  # Update stored percepts with a new one
  defp update_percepts(percept, []) do
    [percept]
  end

  # Update stored percepts with a new one
  defp update_percepts(percept, [previous | others]) do
    [percept, previous | others]
  end

  # Update stored actuated intents with a new one
  defp update_intents(intent, []) do
    [intent]
  end

  # Update stored actuated intents with a new one
  defp update_intents(intent, intents) do
    [intent | intents]
  end

  # Find all matching percepts generated since a given number of seconds
  defp percepts_since(about, secs, state) do
    msecs = now()

    Enum.take_while(
      Map.get(state.percepts, about.sense, []),
      fn percept ->
        secs == nil or percept.until > msecs - secs * 1000
      end
    )
    |> Enum.filter(&Percept.about_match?(&1.about, about))
  end

  # Find all matching intents actuated since a given number of seconds
  defp intents_since(intent_name, secs, state) do
    msecs = now()

    Enum.take_while(
      Map.get(state.intents, intent_name, []),
      fn intent ->
        secs == nil or intent.since > msecs - secs * 1000
      end
    )
  end

  # Find whether a nodel is currently believed in
  defp believed?(conjecture_name, state) do
    case Map.get(state.beliefs, conjecture_name) do
      nil ->
        false

      %Belief{value: believed?} ->
        believed?
    end
  end

  # Forget all expired memories
  defp forget_expired(state) do
    forget_expired_percepts(state)
    |> forget_expired_intents()
  end

  # Forget all expired percepts
  defp forget_expired_percepts(state) do
    msecs = now()

    remembered =
      Enum.reduce(
        Map.keys(state.percepts),
        %{},
        fn sense, acc ->
          unexpired =
            Enum.take_while(
              Map.get(state.percepts, sense),
              fn percept ->
                if percept.ttl == nil or percept.until + percept.ttl > msecs do
                  true
                else
                  Logger.info(
                    "Forgot #{inspect(percept.about)} = #{inspect(percept.value)} after #{
                      div(msecs - percept.until, 1000)
                    } secs"
                  )

                  false
                end
              end
            )

          Map.put_new(acc, sense, unexpired)
        end
      )

    %{state | percepts: remembered}
  end

  # Forget all expired actuated intents
  defp forget_expired_intents(state) do
    msecs = now()

    remembered =
      Enum.reduce(
        Map.keys(state.intents),
        %{},
        fn name, acc ->
          case Map.get(state.intents, name, []) do
            [] ->
              Map.put_new(acc, name, [])

            intents ->
              expired = Enum.filter(intents, &(&1.since + @intent_ttl < msecs))
              # Logger.debug("Forgot #{name} intents #{inspect expired}")
              Map.put(acc, name, intents -- expired)
          end
        end
      )

    %{state | intents: remembered}
  end
end
