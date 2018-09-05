defmodule Matrix.Upload do
  @derive [Poison.Encoder]
  defstruct [:content_uri]
end
