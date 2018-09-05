defmodule MxBridge.XmppBridgeBot do
  use GenServer
  require Logger

  alias Romeo.Stanza
  alias Romeo.Connection, as: Conn
  alias MxBridge.MessageMapper

  @name __MODULE__

  # GenServer methods

  def start_link(xmpp_config) do
    GenServer.start_link(__MODULE__, xmpp_config, name: @name)
  end

  def init(xmpp_config) do
    opts = [jid: xmpp_config.jid, password: xmpp_config.password]
    {:ok, conn} = Conn.start_link(opts)

    {:ok, %{conn: conn, user_name: xmpp_config.user_name, rooms: [], queue: []}}
  end

  # Client API methods

  def join_room(room) do
    GenServer.cast(@name, {:join_room, room})
  end

  def leave_room(room) do
    GenServer.cast(@name, {:leave_room, room})
  end

  def send_group_message(room, from, text) do
    GenServer.cast(@name, {:send_group_message, room, from, text})
  end

  # GenServer callbacks

  def handle_cast({:join_room, room}, state = %{conn: conn, user_name: user_name, rooms: rooms}) do
    :ok = Conn.send(conn, Stanza.join(room, user_name))

    {:noreply, %{state | rooms: rooms ++ [room]}}
  end

  def handle_cast({:leave_room, _room}, state) do
    # Won't this just happen if the bot is leaving a room by itself?
    # TODO Maybe leave room & adjust state
    {:noreply, state}
  end

  def handle_cast({:send_group_message, room, from, text}, state) do
    stanza = Stanza.groupchat(room, "#{from} #{text}")
    state = send_stanza(stanza, state)

    {:noreply, state}
  end

  def handle_info({:stanza, msg = %Stanza.Message{type: type, from: from_jid, body: body}}, state = %{user_name: user_name}) do
    %Romeo.JID{full: full_jid, resource: user} = from_jid

    if String.trim(body) == "" do
      Logger.warn "Ignoring empty xmpp groupchat message #{inspect msg}"
    else
      if user != user_name do
        bare_jid = Romeo.JID.bare(full_jid)
				# FIXME Find a better way to recognize uploads
				upload_data = if String.contains?(inspect(msg.xml), "jabber:x:oob") do
          Logger.debug "Downloading #{body} from XMPP server"
          response = %HTTPoison.Response{body: data} = HTTPoison.get!(body)
          Logger.debug "Got content with #{byte_size(data)} bytes, response: #{inspect response}"
          data
        end
        MessageMapper.xmpp_message(type, %{room: bare_jid, user: user, text: body, upload_data: upload_data})
      end
    end

    {:noreply, state}
  end

  def handle_info({:stanza, %Romeo.Stanza.Presence{type: "error", xml: xml}}, state) do
    # This is ugly. Is the reply really ordered like this on any server?
    # FIXME Find a better way to parse and detect failed joins.
    Logger.debug "Got presence error with xml: #{inspect xml}"
    elements = Tuple.to_list(xml)
    [:xmlel, "presence", props, error] = elements
    case error do
      [{:xmlel, "error", [{"code", "407"}, {"type", "auth"}], _} | _tail] ->
        [{"type", "error"}, {"to", _}, {"from", from}] = props
        [room_id, _] = String.split(from, "/")
        MessageMapper.join_failed :xmpp, room_id
      _ ->
        Logger.debug "Got unknown presence error: #{inspect error}"
    end

    {:noreply, state}
  end

  def handle_info({:stanza, msg}, state) do
    Logger.debug "Ignoring stanza #{inspect msg}"
    {:noreply, state}
  end

  def handle_info({:resource_bound, _}, state) do
    {:noreply, state}
  end

  def handle_info(:connection_ready, state = %{conn: conn, user_name: user_name, queue: queue, rooms: rooms}) do
    Logger.debug "Connection ready for XMPP bridge, announcing presence & getting roster"

    :ok = Conn.send(conn, Stanza.presence)
    :ok = Conn.send(conn, Stanza.get_roster)

    Logger.debug "Joining rooms #{inspect rooms}"
    Enum.each rooms, fn(room) ->
      :ok = Conn.send(conn, Stanza.join(room, user_name))
    end

    Logger.debug "Processing queue (#{inspect queue})"
    queue = process_queue(queue, conn)

    {:noreply, %{state | queue: queue}}
  end

  # Private methods

  defp send_stanza(stanza, state = %{conn: conn, queue: queue}) do
    Logger.debug "Sending stanza #{inspect stanza}"
    queue = process_queue(queue ++ [stanza], conn)
    %{state | queue: queue}
  end

  defp process_queue([stanza | rest] = queue, conn) do
    case Conn.send(conn, stanza) do
      :ok -> process_queue(rest, conn)
      {:error, :closed} -> queue
      {:error, other} ->
        Logger.debug "Error during XMPP send: #{inspect other}"
        queue
    end
  end

  defp process_queue([], _) do
    []
  end
end
