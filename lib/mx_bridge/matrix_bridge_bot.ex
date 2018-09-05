defmodule MxBridge.MatrixBridgeBot do
  use GenServer

  alias MxBridge.MatrixBridgeBotRooms
  alias MxBridge.MessageMapper

  require Logger

  @name __MODULE__

  def start_link(session = %Matrix.Session{}) do
    GenServer.start_link(__MODULE__, session, name: @name)
  end

  def init(session = %Matrix.Session{}) do
    {:ok, %{session: session}}
  end

  # Client API

  def join_room(room) do
    GenServer.call(@name, {:join_room, room})
  end

  def leave_room(room) do
    GenServer.cast(@name, {:leave_room, room})
  end

  def send_group_message(room, from, type, text) do
    GenServer.cast(@name, {:send_group_message, room, from, type, text})
  end

  def new_message_events(events) do
    GenServer.cast(@name, {:new_message_events, events})
  end

  def upload_content!(data, mime_type) do
    GenServer.call(@name, {:upload_content!, data, mime_type})
  end

  def load_mappings(room) do
    GenServer.call(@name, {:load_mappings, room})
  end

  def save_mappings(room, mappings) do
    GenServer.cast(@name, {:save_mappings, room, mappings})
  end

  # GenServer callbacks

  def handle_call({:join_room, room_alias}, _from, state = %{session: session = %Matrix.Session{}}) do
    case Matrix.Client.join(session, room_alias) do
      {:ok, %Matrix.Room{room_id: room_id}} ->
        MatrixBridgeBotRooms.remember(room_id, room_alias)
        {:reply, :ok, state}
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:upload_content!, data, mime_type}, _from, state = %{session: session = %Matrix.Session{}, }) do
    response = Matrix.Client.post_upload!(session, data, mime_type)

    {:reply, response.content_uri, state}
  end

  def handle_call({:load_mappings, room}, _from, state = %{session: session = %Matrix.Session{}, }) do
    room_id = resolve_room_id(room)
    response = case Matrix.Client.get_state_event!(session, %Matrix.Room{room_id: room_id}, "m.net.mxbridge.room_mappings") do
      {:ok, %{"mappings" => mappings}} ->
        mappings
          |> Enum.map(fn %{"matrix" => matrix_room, "xmpp" => xmpp_room} -> %{matrix: matrix_room, xmpp: xmpp_room} end)
      {:error, _errcode} -> []
    end

    {:reply, response, state}
  end


  def handle_cast({:leave_room, room}, state = %{session: session = %Matrix.Session{}}) do
    room_id = resolve_room_id(room)
    Matrix.Client.leave!(session, room_id)

    {:noreply, state}
  end

  def handle_cast({:send_group_message, room, from, type, text}, state = %{session: session = %Matrix.Session{}}) when type in [:text, :notice] do
    msg_type = case type do
      :text -> "m.text"
      :notice -> "m.notice"
    end
    room_id = resolve_room_id(room)
    Logger.debug "Posting #{text} to matrix room #{room} (#{room_id})"
    Matrix.Client.post! session, %Matrix.Room{room_id: room_id}, "#{from} #{text}", msg_type

    {:noreply, state}
  end

  def handle_cast({:send_group_message, room, from, :image, url}, state = %{session: session = %Matrix.Session{}}) do
    room_id = resolve_room_id(room)
    Matrix.Client.post! session, %Matrix.Room{room_id: room_id}, "#{from}:", "m.text"
    Matrix.Client.post! session, %Matrix.Room{room_id: room_id}, "image", "m.image", url

    {:noreply, state}
  end

  def handle_cast({:new_message_events, events}, state = %{session: session = %Matrix.Session{}}) do
    events
    |> filter_non_bot(session)
    |> filter_only_messages
    |> Enum.map(fn event -> resolve_room_alias(event) end)
    |> Enum.each(fn event -> handle_event(event, session) end)

    {:noreply, state}
  end

  def handle_cast({:save_mappings, room, mappings}, state = %{session: session = %Matrix.Session{}, }) do
    room_id = resolve_room_id(room)
    payload = %{mappings: mappings}
    event = Matrix.Client.post_state_event!(session, %Matrix.Room{room_id: room_id}, "m.net.mxbridge.room_mappings", payload)
    Logger.debug "Saved room mapping in #{room}, event id #{event.event_id}"

    {:noreply, state}
  end

  # Private

  defp handle_event(event = %Matrix.Event{content: %Matrix.Content{msgtype: msgtype}}, _session) when msgtype in ["m.text", "m.notice"] do
    MessageMapper.matrix_message("groupchat", %{room: event.room, user: event.sender.user_id, text: event.content.body})
  end

  defp handle_event(event = %Matrix.Event{content: %Matrix.Content{msgtype: "m.image", url: url}}, session = %Matrix.Session{}) do
    text = download_url(url, session)
    MessageMapper.matrix_message("groupchat", %{room: event.room, user: event.sender.user_id, text: text})
  end

  defp filter_non_bot(events, session) do
    events |> Enum.filter(fn event -> event.sender.user_id != session.user_id end)
  end

  defp filter_only_messages(events) do
    events |> Enum.filter(fn event -> event.type == "m.room.message" end)
  end

  defp resolve_room_alias(event = %Matrix.Event{room: room = %Matrix.Room{}}) do
    %{event | room: %{room_id: room.room_id, alias: MatrixBridgeBotRooms.get(room.room_id)}}
  end

  defp resolve_room_id(id_or_alias) do
    case id_or_alias do
      "!" <> _rest -> id_or_alias
      "#" <> _rest -> MatrixBridgeBotRooms.get(id_or_alias)
    end
  end

  defp download_url(mxc_url, %Matrix.Session{home_server: home_server}) do
    %URI{host: host, path: path} = URI.parse(mxc_url)
    %URI{
      scheme: "https",
      host: home_server,
      path: "/_matrix/media/r0/download/#{URI.encode host}#{URI.encode path}"
    } |> URI.to_string
  end
end
