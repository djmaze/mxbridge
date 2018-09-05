defmodule MxBridge.MatrixBridgeBotListener do
  use GenServer

  alias MxBridge.MatrixBridgeBot
  require Logger

  @name __MODULE__

  def start_link(session = %Matrix.Session{}) do
    GenServer.start_link(__MODULE__, session, name: @name)
  end

  @impl true
  def init(session = %Matrix.Session{}) do
    # Swallow old events
    events = Matrix.Client.events!(session, nil)
    from = events.next_batch

    GenServer.cast(self(), :poll_matrix)
    {:ok, %{session: session, from: from}}
  end

  # GenServer callbacks

  @impl true
  def handle_cast(:poll_matrix, state = %{session: session = %Matrix.Session{}, from: from}) do
    Logger.debug fn -> "Getting Matrix events since #{from}" end
    try do
      events = Matrix.Client.events!(session, from)

      state = Map.put state, :from, events.next_batch

      message_events = (events.events
                        |> Enum.reject(fn (e) -> e.sender == session.user_id end))

      MatrixBridgeBot.new_message_events(message_events)

      # Poll again for events
      GenServer.cast(self(), :poll_matrix)

      {:noreply, state}
    rescue
      e in HTTPoison.Error ->
        case e.reason do
          :timeout ->
            Logger.error("HTTP timeout! Trying again")
          _ ->
            Logger.error("HTTP error: " <> Atom.to_string(e.reason))
            Logger.error("Trying again in 10 seconds..")
            :timer.sleep(10000)
        end

        # Poll again for events
        GenServer.cast(self(), :poll_matrix)

        {:noreply, state}
    end
  end
end
