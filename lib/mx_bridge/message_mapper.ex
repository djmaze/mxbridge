defmodule MxBridge.MessageMapper do
  use GenServer

  alias MxBridge.XmppBridgeBot
  alias MxBridge.MatrixBridgeBot
  require Logger

  @name __MODULE__

  def start_link(admin_rooms) do
    GenServer.start_link(__MODULE__, admin_rooms, name: @name)
  end

  def init(admin_rooms) do
    join_rooms(admin_rooms.matrix, admin_rooms.xmpp) || raise("Could not join admin rooms")

    room_mappings = load_room_mappings admin_rooms.matrix
    new_state = {room_mappings, admin_rooms}
    if room_mappings do
      Enum.each(room_mappings, fn %{matrix: matrix_room, xmpp: xmpp_room} ->
        unless join_rooms(matrix_room, xmpp_room) do
          unmap_rooms :matrix, matrix_room, new_state
        end
      end)
    end

    {:ok, new_state}
  end

  # Client API

  def xmpp_message(type, data) do
    GenServer.cast(@name, {:xmpp_message, type, data})
  end

  def matrix_message(type, msg) do
    GenServer.cast(@name, {:matrix_message, type, msg})
  end

  def admin_message(type, msg) do
    GenServer.cast(@name, {:admin_message, type, msg})
  end

  def join_failed(network, room_id) do
    GenServer.cast(@name, {:join_failed, network, room_id})
  end

  # GenServer callbacks

  def handle_cast({:xmpp_message, "groupchat", msg}, state = {room_mappings, %{matrix: matrix_admin_room, xmpp: xmpp_admin_room}}) do
    matrix_room = case msg.room do
      ^xmpp_admin_room -> matrix_admin_room
      _ -> map_xmpp_to_matrix(room_mappings, msg.room)
    end

    if matrix_room do
      Logger.debug "Forwarding XMPP groupchat message #{inspect msg} to matrix room #{matrix_room}"

      if msg[:upload_data] do
        {:ok, path} = Briefly.create
        Logger.debug "Writing upload data to tempfile #{path}"
        File.write!(path, msg[:upload_data])
        {mime_type, 0} = System.cmd("file", ["--brief", "--mime-type", path])
        mime_type = String.trim_trailing(mime_type)
        :ok = File.rm(path)

        Logger.debug "Uploading #{path} to Matrix server"
        url = MatrixBridgeBot.upload_content!(msg[:upload_data], mime_type)
        MatrixBridgeBot.send_group_message(matrix_room, "[#{msg.user}]", :image, url)
      else
        MatrixBridgeBot.send_group_message(matrix_room, "[#{msg.user}]", :text, msg.text)
      end

      if msg.room == xmpp_admin_room do
        MatrixBridgeBot.send_group_message(matrix_admin_room, "[#{msg.user}]", :text, msg.text)
        {answer, new_state} = admin_command msg, state
        XmppBridgeBot.send_group_message(msg.room, nil, answer)
        MatrixBridgeBot.send_group_message(matrix_admin_room, "", :notice, answer)
      end
    else
      Logger.warn "Ignoring xmpp groupchat message from unknown room #{inspect msg}"
    end

    {:noreply, new_state || state}
  end

  def handle_cast({:xmpp_message, "chat", msg}, state) do
    # not handled for now
    Logger.debug fn -> "Ignoring chat message #{inspect msg}" end

    {:noreply, state}
  end

  def handle_cast({:xmpp_message, "normal", msg}, state) do
    # not handled for now
    Logger.debug fn -> "Ignoring normal message #{inspect msg}" end

    {:noreply, state}
  end

  def handle_cast({:matrix_message, "groupchat", msg}, state = {room_mappings, %{matrix: matrix_admin_room, xmpp: xmpp_admin_room}}) do
    xmpp_room = case msg.room.alias do
      ^matrix_admin_room -> xmpp_admin_room
      _ -> msg.room.alias |> map_matrix_to_xmpp(room_mappings)
    end

    if xmpp_room do
      Logger.debug "Forwarding matrix groupchat message #{inspect msg} to XMPP room #{xmpp_room}"
      user_part = String.split(msg.user, ":") |> List.first |> String.split("@") |> List.last
      XmppBridgeBot.send_group_message(xmpp_room, "[#{user_part}]", msg.text)

      if msg.room.alias == matrix_admin_room do
        {answer, new_state} = admin_command msg, state
        MatrixBridgeBot.send_group_message(msg.room.room_id, nil, :notice, answer)
        XmppBridgeBot.send_group_message(xmpp_room, "", answer)
      end
    else
      Logger.warn "Ignoring matrix groupchat message from unknown room #{inspect msg}"
    end

    {:noreply, new_state || state}
  end

  def handle_cast({:admin_message, type, msg}, state = {_room_mappings, %{matrix: matrix_admin_room, xmpp: xmpp_admin_room}}) do
    MatrixBridgeBot.send_group_message(matrix_admin_room, "", type || :text, msg)
    XmppBridgeBot.send_group_message(xmpp_admin_room, "", msg)

    {:noreply, state}
  end

  def handle_cast({:join_failed, network, room_id}, state) do
    admin_message :text, "Error joining #{network} room #{room_id}, unmapping"
    new_state = unmap_rooms(network, room_id, state)

    {:noreply, new_state}
  end

  # Helper methods

  defp map_xmpp_to_matrix(room_mappings, xmpp_room) do
    room_mappings
      |> Enum.find(fn m -> m.xmpp == xmpp_room end)
      |> Map.get(:matrix)
  end

  defp map_matrix_to_xmpp(matrix_room, room_mappings) do
    room_mappings
      |> Enum.find(%{}, fn m -> m.matrix == matrix_room end)
      |> Map.get(:xmpp)
  end

  defp admin_command(msg, state = {room_mappings, admin_rooms = %{matrix: matrix_admin_room}}) do
    [cmd | args] = String.split(msg.text, " ")
    answer = case String.downcase(cmd) do
      "ping" -> "pong"
      "help" ->
        "Commands: ping, rooms, map, unmap"
      "rooms" ->
        room_string = room_mappings
          |> Enum.map(fn %{matrix: matrix_room, xmpp: xmpp_room} -> "* #{matrix_room} => #{xmpp_room}" end)
          |> Enum.join("\n")
        "Current rooms:\n#{room_string}"
      "map" ->
        case args do
          [matrix_room, xmpp_room] ->
            #new_state = map_rooms matrix_room, xmpp_room, state
            case map_rooms matrix_room, xmpp_room, room_mappings do
              {:ok, new_room_mappings} ->
                MatrixBridgeBot.save_mappings matrix_admin_room, new_room_mappings
                new_state = {new_room_mappings, admin_rooms}
                "Ok, joined and mapped #{matrix_room} to #{xmpp_room}"
              {:error} ->
                "Error mapping rooms"
            end
          _ -> "Error, need matrix and xmpp room names"
        end
      "unmap" ->
        case args do
          [matrix_room] ->
            new_state = unmap_rooms :matrix, matrix_room, state
            "Ok, unmapped #{matrix_room}"
          _ -> "Error, need matrix room name"
        end
      _ -> "Error, unknown command \"#{cmd}\""
    end

    {answer, new_state || state}
  end

  defp load_room_mappings(matrix_room) do
    MatrixBridgeBot.load_mappings matrix_room
  end

  defp map_rooms(matrix_room, xmpp_room, room_mappings) do
    if join_rooms(matrix_room, xmpp_room) do
      {:ok, room_mappings ++ [%{matrix: matrix_room, xmpp: xmpp_room}]}
    else
      {:error}
    end
  end

  defp unmap_rooms(network, room_id, {room_mappings, admin_rooms}) do
    rooms = Enum.find(room_mappings, fn m -> m[network] == room_id end)
    if rooms do
      MatrixBridgeBot.leave_room(rooms.matrix)
      XmppBridgeBot.leave_room(rooms.xmpp)

      new_room_mappings = Enum.reject(room_mappings, fn m -> m[network] == room_id end)
      MatrixBridgeBot.save_mappings admin_rooms[:matrix], new_room_mappings
      {new_room_mappings, admin_rooms}
    else
      {room_mappings, admin_rooms}
    end
  end

  defp join_rooms(matrix_room, xmpp_room) do
    case MatrixBridgeBot.join_room matrix_room do
      :ok ->
        XmppBridgeBot.join_room xmpp_room
        true
      {:error, %{"error" => msg}} ->
        admin_message(:text, "Join error: #{msg}")
        false
    end
  end
end
