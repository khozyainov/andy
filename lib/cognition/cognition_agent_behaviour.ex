defmodule Andy.CognitionAgentBehaviour do

  @type state :: any()
  @type event :: any()

  @callback handle_event(event(), state()) :: state()
  @callback start_link() :: {:ok, pid()}

end