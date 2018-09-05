defmodule Matrix.Client do
  alias Matrix.Sessions

  def login!(%Matrix.Config{home_server: home_server, user: user, password: password}) do
    data = %{user: user, password: password, type: "m.login.password"}
    response = HTTPoison.post!("https://#{home_server}/_matrix/client/r0/login", Poison.encode!(data), [], timeout: 10_000)

    Poison.decode!(response.body, as: Matrix.Session)
  end

  def resolve_room_id!(session, alias) do
    room_response = HTTPoison.get!("https://#{session.home_server}/_matrix/client/r0/directory/room/#{alias}?access_token=#{session.access_token}", timeout: 10_000)

    Poison.decode!(room_response.body, as: Matrix.Room)
  end

  def join(session, room_name) do
    %HTTPoison.Response{status_code: status, body: body} = HTTPoison.post!("https://#{session.home_server}/_matrix/client/r0/join/#{room_name}?access_token=#{session.access_token}", "", [], timeout: 10_000)

    case status do
      200 ->
        {:ok, Poison.decode!(body, as: Matrix.Room)}
      _ ->
        {:error, Poison.decode!(body)}
    end
  end

  def leave!(session, room_id) do
    # Ignoring response for now
    %HTTPoison.Response{status_code: 200} = HTTPoison.post!("https://#{session.home_server}/_matrix/client/r0/rooms/#{room_id}/leave?access_token=#{session.access_token}", "", [], timeout: 10_000)
  end

  def events!(session, since \\ nil) do
    params = [timeout: 30000, access_token: session.access_token]

    if since do
      params = Keyword.put params, :since, since
    end

    response = HTTPoison.get!("https://#{session.home_server}/_matrix/client/r0/sync", ["Accept": "application/json"], params: params, recv_timeout: 40000, timeout: 10_000)

    data = Poison.decode!(response.body)
    Matrix.ResponseConstructer.events(data)
  end

  def post!(session = %Matrix.Session{}, room = %Matrix.Room{}, message, msg_type \\ "m.text", url \\ nil, event_type \\ "m.room.message") do
    data = %{msgtype: msg_type, body: message, url: url}

    txid = new_txid(session)

    %HTTPoison.Response{status_code: 200, body: body} = HTTPoison.put!("https://#{session.home_server}/_matrix/client/r0/rooms/#{room.room_id}/send/#{event_type}/#{txid}?access_token=#{session.access_token}", Poison.encode!(data))

    Poison.decode!(body, as: Matrix.EventId)
  end

  def post_upload!(session = %Matrix.Session{}, content, content_type) do
    response = HTTPoison.post!("https://#{session.home_server}/_matrix/media/r0/upload?access_token=#{session.access_token}", content, [{"Content-Type", content_type}])

    Poison.decode!(response.body, as: Matrix.Upload)
  end

  def get_state_event!(session = %Matrix.Session{}, room = %Matrix.Room{}, event_type) do
    %HTTPoison.Response{status_code: status, body: body} = HTTPoison.get!("https://#{session.home_server}/_matrix/client/r0/rooms/#{room.room_id}/state/#{event_type}?access_token=#{session.access_token}")
    data = Poison.decode!(body)
    case status do
      200 -> {:ok, data}
      _ ->
        %{"errcode" => errcode} = data
        {:error, errcode}
    end
  end

  def post_state_event!(session = %Matrix.Session{}, room = %Matrix.Room{}, event_type, data) do
    %HTTPoison.Response{status_code: 200, body: body} = HTTPoison.put!("https://#{session.home_server}/_matrix/client/r0/rooms/#{room.room_id}/state/#{event_type}?access_token=#{session.access_token}", Poison.encode!(data))

    Poison.decode!(body, as: Matrix.EventId)
  end

  def new_txid(session) do
    Sessions.get_and_increase_txid(sessions(), session)
  end

  defp sessions do
    case Sessions.start_link {} do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end
