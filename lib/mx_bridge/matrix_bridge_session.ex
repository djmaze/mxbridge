defmodule MxBridge.MatrixBridgeSession do
  use Supervisor

  require Logger

  @name __MODULE__

  def start_link(matrix_config = %{}) do
    Supervisor.start_link(__MODULE__, matrix_config, name: @name)
  end

  @impl true
  def init(matrix_config = %{}) do
    config = %Matrix.Config{
      home_server: matrix_config.home_server,
      user: matrix_config.user,
      password: matrix_config.password,

    }
    Logger.debug "Logging in to #{matrix_config.home_server}"
    session = Matrix.Client.login!(config)
    session = %{session | home_server: matrix_config.home_server}   # Workaround

    children = [
      {MxBridge.MatrixBridgeBotListener, session},
      MxBridge.MatrixBridgeBotRooms,
      {MxBridge.MatrixBridgeBot, session},
    ]
    Supervisor.init(children, strategy: :one_for_one, name: @name)
  end
end
