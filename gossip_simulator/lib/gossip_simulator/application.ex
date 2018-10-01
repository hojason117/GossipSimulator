defmodule GossipSimulator.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    GossipSimulator.Supervisor.start_link(self())
  end
end
