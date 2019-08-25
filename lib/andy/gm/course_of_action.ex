defmodule Andy.GM.CourseOfAction do
  @moduledoc "A course of action is a sequence of named Intentions meant to be realized as Intents in an attempt
    to validate some activation of a conjecture"

  alias Andy.GM.{CourseOfAction, Conjecture, ConjectureActivation}
  alias __MODULE__

  defstruct conjecture_activation: nil,
            intention_names: []

  def of_type?(
        %CourseOfAction{
          conjecture_activation: %ConjectureActivation{
            conjecture: %Conjecture{name: coa_conjecture_name}
          },
          intention_names: coa_intention_names
        },
        {conjecture_name, _},
        intention_names
      ) do
    coa_conjecture_name == conjecture_name and coa_intention_names == intention_names
  end
end
