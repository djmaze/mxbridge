defmodule MxBridge.XmppBridgeSession do
  use Supervisor

  @name __MODULE__

  def start_link(xmpp_config = %{}) do
    Supervisor.start_link(__MODULE__, xmpp_config, name: @name)
  end

  def init(xmpp_config = %{}) do
    children = [
      {MxBridge.XmppBridgeBot, xmpp_config}
    ]
    Supervisor.init(children, strategy: :one_for_one, name: @name)
  end
end
