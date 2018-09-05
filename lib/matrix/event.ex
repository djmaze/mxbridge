defmodule Matrix.Event do
  defstruct [:event_id, :age, :sender, :room, :type, :content, :origin_server_ts]
end
