defmodule Andy.Experience do
  @moduledoc """
  Responsible for learning which prediction fulfillments work best
  and trying the better ones more often.
  """

  require Logger
  alias Andy.{ PubSub, Predictor, PredictionError, PredictionFulfilled, Fulfill }
  import Andy.Utils, only: [listen_to_events: 2]

  @name __MODULE__

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        %{
          # %{predictor_name: [{successes, failures}, nil, nil]} -- index in list == fulfillment index
          fulfillment_stats: %{ }
        }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end

  ### Cognition Agent Behaviour

  ## Handle timer events

  def handle_event({ :prediction_error, prediction_error }, state) do
    # Update fulfillment stats
    updated_state = update_fulfillment_stats(prediction_error, state)
    # Choose a fulfillment to correct the prediction error
    fulfillment_index = choose_fulfillment_index(prediction_error, updated_state)
    Logger.info("Experience chose fulfillment #{fulfillment_index} to address #{inspect prediction_error}")
    if fulfillment_index != 0 do
      # Activate fulfillment
      PubSub.notify_fulfill(
        Fulfill.new(predictor_name: prediction_error.predictor_name, fulfillment_index: fulfillment_index)
      )
    end
    updated_state
  end

  def handle_event({ :prediction_fulfilled, predictor_name }, state) do
    update_fulfillment_stats(predictor_name, state)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  defp update_fulfillment_stats(
         %PredictionError{ predictor_name: predictor_name },
         state
       ) do
    learn_from_success_or_failure(predictor_name, :failure, state)
  end

  defp update_fulfillment_stats(
         %PredictionFulfilled{ predictor_name: predictor_name },
         state
       )  do
    learn_from_success_or_failure(predictor_name, :success, state)
  end

  defp learn_from_success_or_failure(
         predictor_name,
         success_or_failure,
         %{ fulfillment_stats: fulfillment_stats } = state
       ) do
    { fulfillment_index, fulfillment_count } = Predictor.fulfillment_data(predictor_name)
    Logger.warn("Fulfillment data = #{inspect { fulfillment_index, fulfillment_count } } from predictor #{predictor_name}")
       # The predictor has an active fulfillment we are learning about
      new_predictor_stats = case Map.get(fulfillment_stats, predictor_name) do
        nil ->
          initial_predictor_stats = List.duplicate({ 0, 0 }, fulfillment_count)
          Logger.warn("New predictor stats = #{inspect initial_predictor_stats}")
          capture_success_or_failure(initial_predictor_stats, fulfillment_index, success_or_failure)
        predictor_stats ->
          Logger.warn("Prior predictor stats = #{inspect predictor_stats}")
          capture_success_or_failure(predictor_stats, fulfillment_index, success_or_failure)
      end
      updated_fulfillment_stats = Map.put(fulfillment_stats, predictor_name, new_predictor_stats)
      %{ state | fulfillment_stats: updated_fulfillment_stats }
  end

  defp capture_success_or_failure(predictor_stats, nil, _success_or_failure) do
    predictor_stats
  end

  defp capture_success_or_failure(predictor_stats, fulfillment_index, success_or_failure) do
    stats = Enum.at(predictor_stats, fulfillment_index - 1)
    List.replace_at(predictor_stats, fulfillment_index, increment(stats, success_or_failure))
  end

  defp increment({ successes, failures }, :success) do
    { successes + 1, failures }
  end

  defp increment({ successes, failures }, :failure) do
    { successes, failures + 1 }
  end

  # Returns a number between 1 and the number of alternative fulfillments a prediction has (inclusive),
  # or returns 0 if no choice available
  defp choose_fulfillment_index(
         %{ predictor_name: predictor_name } = _prediction_error,
         %{ fulfillment_stats: fulfillment_stats } = _state
       ) do
    ratings = for { successes, failures } <- Map.get(fulfillment_stats, predictor_name, []) do
      # A fulfillment has a 10% minimum probability of being selected
      if successes == 0, do: 0.1, else: max(successes / (successes + failures), 0.1)
    end
    Logger.warn("Ratings = #{inspect ratings} given stats #{inspect fulfillment_stats} for predictor #{predictor_name}")
    if Enum.count(ratings) == 0 do
      0
    else
      ratings_sum = Enum.reduce(ratings, 0.0, fn (r, acc) -> r + acc end)
      spreads = Enum.map(ratings, &(&1 / ratings_sum))
      { ranges_reversed, _ } = Enum.reduce(
        spreads,
        { [], 0 },
        fn (spread, { ranges_acc, top_acc }) ->
          { [top_acc + spread | ranges_acc], top_acc + spread }
        end
      )
      ranges = Enum.reverse(ranges_reversed)
      random = Enum.random(1..1000) / 1000
      Enum.find(1..Enum.count(ranges), &(random < Enum.at(ranges, &1 - 1)))
    end
  end

end