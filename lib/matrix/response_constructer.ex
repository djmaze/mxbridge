defmodule Matrix.ResponseConstructer do
  def events(response) do
    %Matrix.Events{
      events: response["rooms"]["join"] |> Enum.flat_map(&room/1),
      next_batch: response["next_batch"]
    }
  end

  def room({room_id, response}) do
    response["timeline"]["events"]
    |> Enum.map(fn event -> Map.put(event, "room_id", room_id) end)
    |> Enum.map(&event/1)
  end

  def room(rooms = [_ | _]) do
    rooms |> room()
  end

  def room(room_id) do
    %Matrix.Room{room_id: room_id}
  end

  def event(response) do
    %Matrix.Event{
      event_id: response["event_id"],
      age: response["age"],
      content: content(response["type"], response["content"]),
      room: room(response["room_id"]),
      type: response["type"],
      origin_server_ts: response["origin_server_ts"],
      sender: user(response["sender"]),
    }
  end

  def content("m.typing", response) do
    %Matrix.Content{
      users: Enum.map(response["user_ids"] , &user/1)
    }
  end

  def content("m.room.message", response) do
    %Matrix.Content{
      body: response["body"],
      msgtype: response["msgtype"],
      url: response["url"]
    }
  end

  def content(_type, _response) do
    %Matrix.Content{}
  end

  def user(nil) do
    nil
  end

  def user(user_id) do
    %Matrix.User{user_id: user_id}
  end
end
