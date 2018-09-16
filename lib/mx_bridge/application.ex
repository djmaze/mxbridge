defmodule MxBridge.Application do
  use Application

  def start(_type, _args) do
    {:ok, xmpp_config} = Confex.fetch_env(:mxbridge, :xmpp)
    {:ok, matrix_config} = Confex.fetch_env(:mxbridge, :matrix)
    {:ok, admin_rooms} = Confex.fetch_env(:mxbridge, :admin_rooms)
    {:ok, log_level} = Confex.fetch_env(:mxbridge, :log_level)
    Logger.configure level: String.to_atom(log_level)

    children = [
      {MxBridge.XmppBridgeSession, xmpp_config},
      {MxBridge.MatrixBridgeSession, matrix_config},
      {MxBridge.MessageMapper, admin_rooms}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MxBridge.Supervisor)
  end

  def stop(_) do
    System.stop
  end
end
