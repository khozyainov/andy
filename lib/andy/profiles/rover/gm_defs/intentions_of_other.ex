defmodule Andy.Profiles.Rover.GMDefs.IntentionsOfOther do
  @moduledoc "The GM definition for :intentions_of_other"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :intentions_of_other,
      conjectures: [
        conjecture(:other_panicking),
        conjecture(:other_homing_on_food)
      ],
      # allow all conjectures to be activated
      contradictions: [],
      priors: %{
        other_panicking: %{is: false},
        other_homing_on_food: %{is: false}
      },
      intentions: %{
        say_other_panicking: %Intention{
          intent_name: :say,
          valuator: panicking_opinion_valuator(),
          repeatable: false
        },
        say_other_homing_on_food: %Intention{
          intent_name: :say,
          valuator: homing_on_food_opinion_valuator(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:other_panicking) do
    %Conjecture{
      name: :other_panicking,
      # Only activate if actively observing the robot
      activator: behavior_activator(),
      predictors: [
        no_change_predictor(:observed, default: %{is: false, distance: -128, heading: 0})
      ],
      valuator: other_panicking_belief_valuator(),
      intention_domain: [:say_other_panicking]
    }
  end

  defp conjecture(:other_homing_on_food) do
    %Conjecture{
      name: :other_homing_on_food,
      # Only activate if actively observing the robot
      activator: behavior_activator(),
      predictors: [
        no_change_predictor(:observed, default: %{is: false, distance: -128, heading: 0})
      ],
      valuator: other_homing_on_food_belief_valuator(),
      intention_domain: [:say_other_homing_on_food]
    }
  end

  # Conjecture activators

  defp behavior_activator() do
    fn conjecture, [round | _previous_rounds], _prediction_about ->
      observed? = current_perceived_value(round, :other, :observed, :is, defaut: false)

      if observed? do
        [
          Conjecture.activate(conjecture,
            about: :other
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp other_panicking_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      observations =
        recent_perceived_values(rounds, about, :observed,
          matching: %{is: true},
          since: now() - 10_000
        )

      distances = Enum.map(observations, &Map.get(&1, :distance, 0))
      headings = Enum.map(observations, &Map.get(&1, :heading, 0))

      panicking? =
        Enum.count(observations) > 4 and
          variability(distances) > 3 and
          variability(headings) > 3

      %{is: panicking?}
    end
  end

  defp other_homing_on_food_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      observations =
        recent_perceived_values(rounds, about, :observed,
          matching: %{is: true},
          since: now() - 10_000
        )

      distances = Enum.map(observations, &Map.get(&1, :distance, 0))
      headings = Enum.map(observations, &Map.get(&1, :heading, 0))

      homing? =
        Enum.count(observations) > 4 and
          count_changes(distances) > 4 and
          variability(distances) <= 1 and
          variability(headings) <= 1

      %{is: homing?}
    end
  end

  # Intention valuators

  defp panicking_opinion_valuator() do
    fn %{is: true} ->
      "#{Andy.name_of_other()} is freaking out"
    end

    fn _ ->
      nil
    end
  end

  defp homing_on_food_opinion_valuator() do
    fn %{is: true} ->
      "#{Andy.name_of_other()} has found food"
    end

    fn _ ->
      nil
    end
  end
end