defmodule GossipSimulator do
  def start do
    {:ok, _} = GossipSimulator.Supervisor.start_link(self())
    receive do
      {:done, result} -> output(result)
    end
  end

  defp output(time) do
    IO.puts "Duration: #{time} (sec)"
  end
end
