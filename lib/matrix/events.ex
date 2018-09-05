defmodule Matrix.Events do
  @derive [Poison.Encoder]
  defstruct [:events, :next_batch]
end
