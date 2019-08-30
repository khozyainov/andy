defmodule Andy.GM.Belief do
  @moduledoc "A belief by a detector or generative model"

  alias __MODULE__
  import Andy.Utils, only: [does_match?: 2]

  defstruct source: nil, # GM name or detector name
            # conjecture name if from a GM, else detector name is from a detector
            conjecture_name: nil,
            # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            about: nil,
            # the goal, if any, to be achieved
            goal: nil,
            # value_name => value, or nil if disbelief
            values: nil

  def new(
        source: source,
        conjecture_name: conjecture_name,
        about: about,
        goal: goal,
        values: values
      ) do
    %Belief{
      source: source,
      conjecture_name: conjecture_name,
      about: about,
      goal: goal,
      values: values
    }
  end

  def values(%Belief{values: values}) do
    values
  end

  def believed?(%Belief{values: values}) do
    values != nil
  end

  def satisfies_conjecture?(%Belief{values: nil} ) do
    false
  end

  def satisfies_conjecture?(%Belief{goal: nil, values: values}) do
    values != nil
  end

  def satisfies_conjecture?(%Belief{goal: goal, values: values}) do
    goal.(values)
  end

  def subject(%Belief{conjecture_name: conjecture_name, about: about}) do
    {conjecture_name, about}
  end

  def values_match?(%Belief{values: values}, values), do: true
  def values_match?(%Belief{values: _values}, _other_values), do: false

  def has_value?(%Belief{values: belief_values}, value_name, value) do
    does_match?(Map.get(belief_values, value_name), value)
  end

  @doc "Is this belief from a generative model?"
  def from_generative_model?(%Belief{source: source}) do
    source not in [:detector, :prediction]
  end
end