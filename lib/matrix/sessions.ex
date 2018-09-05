defmodule Matrix.Sessions do
  use Agent

  @name __MODULE__

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: @name)
  end

  def add(pid, session) do
    Agent.update(pid, &Map.put(&1, session.access_token, 1))
    session
  end

  def get_and_increase_txid(pid, session) do
    Agent.get_and_update(pid, &Map.get_and_update(&1, session.access_token, fn current ->
      case current do
        nil -> {1, 2}
        number -> {number, number + 1}
      end
    end))
  end

end
