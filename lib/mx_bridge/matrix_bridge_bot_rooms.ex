defmodule MxBridge.MatrixBridgeBotRooms do
  use Agent

  require Logger

  @name __MODULE__

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: @name)
  end

  def remember(room_id, room_alias) do
    remember(@name, room_id, room_alias)
  end

  def get(id_or_alias) do
    get(@name, id_or_alias)
  end

  defp remember(pid, room_id, room_alias) do
    Logger.debug "Remembering room alias #{room_alias} for #{room_id}"
    Agent.update(pid, &Map.put(&1, room_id, room_alias))
    Agent.update(pid, &Map.put(&1, room_alias, room_id))
  end

  defp get(pid, id_or_alias) do
    Agent.get(pid, fn rooms = %{} -> rooms[id_or_alias] end)
  end

  # TODO We should be able to forget room aliases as well
end
