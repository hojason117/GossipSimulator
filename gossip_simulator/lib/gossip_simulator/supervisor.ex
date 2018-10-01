defmodule GossipSimulator.Supervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(arg) do
    if Enum.at(System.argv(), 2) == nil do
      IO.puts "Invalid inputs."
      {:invalid_argv}
    else
      registry = {Registry, keys: :unique, name: GossipSimulator.Registry, partitions: System.schedulers_online()}

      share_arg = %{total_nodes: System.argv() |> Enum.at(0) |> String.to_integer() |> round_total_nodes(Enum.at(System.argv(), 1)), topology: Enum.at(System.argv(), 1), algo: Enum.at(System.argv(), 2)}

      share_arg =
        if Enum.at(System.argv(), 3) |> String.slice(0..1) == "-f" do
          Map.merge(share_arg, %{fail_mode: true, fail_rate: System.argv() |> Enum.at(3) |> String.slice(3..5) |> String.to_integer()})
        else
          Map.put(share_arg, :fail_mode, false)
        end

      manager = Supervisor.child_spec({GossipSimulator.Manager, [Map.put(share_arg, :original_total_nodes, System.argv() |> Enum.at(0) |> String.to_integer()), arg]}, restart: :transient)

      participants = Enum.reduce(share_arg.total_nodes..1, [],
        fn(x, acc) -> [Supervisor.child_spec({GossipSimulator.Participant, [share_arg, x]}, id: {GossipSimulator.Participant, x}, restart: :transient) | acc] end)

      children = [registry | participants] ++ [manager]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  # Round total_nodes to the next nearest perfect square for torus topology and perfect cube for 3D topology.
  defp round_total_nodes(total_nodes, topology) do
    case topology do
      "3D" ->
        if :math.pow(trunc(:math.pow(total_nodes, 0.33)), 3) == total_nodes do
          total_nodes
        else
          new_total_nodes = trunc(:math.pow(trunc(:math.pow(total_nodes, 0.33)) + 1, 3))
          IO.puts "Round total nodes for 3D topology to #{new_total_nodes}..."
          new_total_nodes
        end
      "torus" ->
        if :math.pow(trunc(:math.sqrt(total_nodes)), 2) == total_nodes do
          total_nodes
        else
          new_total_nodes = trunc(:math.pow(trunc(:math.sqrt(total_nodes)) + 1, 2))
          IO.puts "Round total nodes for torus topology to #{new_total_nodes}..."
          new_total_nodes
        end
      _ ->
        total_nodes
    end
  end
end
