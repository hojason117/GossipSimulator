defmodule GossipSimulator.Manager do
  use GenServer

  @gossip_content "Elixir is fun!!"
  @rand2D_neighbor_distance 0.1
  @rand2D_neighbor_approx_distance @rand2D_neighbor_distance * 1.5
  @rand2D_neighbor_distance_square @rand2D_neighbor_distance * @rand2D_neighbor_distance

  # Client

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: GossipSimulator.Manager)
  end

  def gossip_content, do: @gossip_content

  # Server (callbacks)

  def init(arg) do
    GenServer.cast(self(), :start)
    participants_checklist = Enum.reduce(1..Enum.at(arg, 0).total_nodes, %{}, fn(x, acc) -> Map.put(acc, "participant_#{x}", false) end)
    new_state =
      case Enum.at(arg, 0).algo do
        "gossip" ->
          Map.merge(Enum.at(arg, 0), %{output: Enum.at(arg, 1), participants_heard: participants_checklist, participants_heard_count: 0, progress: 0, converged: false, timer: spawn(fn() -> :ok end)})
        "push-sum" ->
          Map.merge(Enum.at(arg, 0), %{output: Enum.at(arg, 1), message_count: 0, last_message_print: 0})
      end
    {:ok, new_state}
  end

  def handle_cast(:start, state) do
    IO.puts "Assigning neighbors..."
    assign_neighbors(state)
    :timer.sleep(500)
    new_state = Map.put(state, :start_time, Time.utc_now())
    case new_state.algo do
      "gossip" ->
        IO.puts "Start gossiping..."
        :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{Enum.random(1..state.total_nodes)}"}}, {:gossip, @gossip_content})
      "push-sum" ->
        IO.puts "Start pushing..."
        :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{Enum.random(1..state.total_nodes)}"}}, :start_push)
    end
    {:noreply, new_state}
  end

  def handle_cast(:receive_sum, state) do
    new_state = Map.put(state, :message_count, state.message_count + 1)
    new_state =
      if new_state.message_count - new_state.last_message_print == 50000 do
        IO.write("\rPushing" <> Enum.reduce(0..2, "", fn(x, acc) -> if x <= ((new_state.message_count / 50000 - 1) |> trunc() |> rem(3)), do: acc <> ".", else: acc <> " " end))
        Map.put(new_state, :last_message_print, new_state.message_count)
      else
        new_state
      end
    {:noreply, new_state}
  end

  def handle_call({:heard_gossip, target}, from, state) do
    GenServer.reply(from, :ok)
    Process.exit(state.timer, :kill)

    unless state.participants_heard[target] do
      new_participants_heard = Map.put(state.participants_heard, target, true)
      new_state = Map.merge(state, %{participants_heard: new_participants_heard, participants_heard_count: state.participants_heard_count + 1})
      new_state = Map.put(new_state, :progress, print_gossip_progress(new_state))
      if new_state.participants_heard_count == new_state.total_nodes do
        new_state = Map.merge(new_state, %{end_time: Time.utc_now(), converged: true})
        terminate_participants(new_state.algo, new_state.total_nodes)
        {:stop, :normal, new_state}
      else
        new_state = Map.put(new_state, :timer, spawn(fn() -> countdown() end))
        {:noreply, new_state}
      end
    else
      new_state = Map.put(state, :timer, spawn(fn() -> countdown() end))
      {:noreply, new_state}
    end
  end

  def handle_call({:stop_pushing, reason, sum}, from, state) do
    GenServer.reply(from, :ok)
    new_state = Map.merge(state, %{end_time: Time.utc_now(), sum: sum})
    terminate_participants(new_state.algo, new_state.total_nodes)
    case reason do
      :fail_node ->
        IO.puts "\nPush-sum terminated: encounter failure node"
      :no_neighbor ->
        IO.puts "\nPush-sum terminated: node has 0 neighbors"
      :stopped ->
        IO.puts "\nPush-sum terminated: stopping criteria reached"
    end
    {:stop, :normal, new_state}
  end

  def handle_info(:timesup, state) do
    new_state = Map.put(state, :end_time, Time.utc_now())
    terminate_participants(new_state.algo, new_state.total_nodes)
    {:stop, :normal, new_state}
  end

  def terminate(reason, state) do
    if reason == :normal do
      case state.algo do
        "gossip" ->
          if state.converged do
            IO.puts "\nAll nodes propagated, convergence achieved."
          else
            IO.puts "\nConvergence not achieved, only #{state.participants_heard_count}/#{state.total_nodes} nodes propagated."
          end
        "push-sum" ->
          IO.puts "Sum: #{state.sum}"
      end
      send(state.output, {:done, Time.diff(state.end_time, state.start_time, :second)})
    else
      IO.inspect(reason)
      send(state.output, {:done, -1})
    end
  end

  # Aux

  defp assign_neighbors(state) do
    if state.total_nodes == 1 do
      :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_1"}}, {:assigned_neighbors, []})
    else
      case state.topology do
        "full" ->
          Enum.each(1..state.total_nodes,
            fn(x) ->
              :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{x}"}}, {:assigned_neighbors, 1..state.total_nodes |> Enum.filter(fn(y) -> x != y end) |> Enum.to_list()})
            end)
        "3D" ->
          side = trunc(:math.pow(state.original_total_nodes, 0.33)) + 1
          Enum.each(1..side,
            fn(i) ->
              Enum.each(1..side,
                fn(j) ->
                  Enum.each(1..side,
                    fn(k) ->
                      right = if valid_3d_coordinate?(i, j, k + 1, side), do: [coordinate_3d_to_1d(i, j, k + 1, side)], else: []
                      left = if valid_3d_coordinate?(i, j, k - 1, side), do: [coordinate_3d_to_1d(i, j, k - 1, side)], else: []
                      down = if valid_3d_coordinate?(i, j + 1, k, side), do: [coordinate_3d_to_1d(i, j + 1, k, side)], else: []
                      up = if valid_3d_coordinate?(i, j - 1, k, side), do: [coordinate_3d_to_1d(i, j - 1, k, side)], else: []
                      below = if valid_3d_coordinate?(i + 1, j, k, side), do: [coordinate_3d_to_1d(i + 1, j, k, side)], else: []
                      above = if valid_3d_coordinate?(i - 1, j, k, side), do: [coordinate_3d_to_1d(i - 1, j, k, side)], else: []
                      neighbors = right ++ left ++ down ++ up ++ below ++ above
                      :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{coordinate_3d_to_1d(i, j, k, side)}"}}, {:assigned_neighbors, neighbors})
                    end)
                end)
            end)
        "rand2D" ->
          x_axis = Enum.reduce(1..state.total_nodes, [], fn(_x, acc) -> [Enum.random(0..1000) / 1000 | acc] end)
          y_axis = Enum.reduce(1..state.total_nodes, [], fn(_x, acc) -> [Enum.random(0..1000) / 1000 | acc] end)
          Enum.each(1..state.total_nodes,
            fn(i) ->
              nodes_without_self = Enum.filter(1..state.total_nodes, fn(j) -> j != i end)
              neighbors = Enum.reduce(nodes_without_self, [],
                fn(k, acc) ->
                  if rand2D_neighbor?(Enum.at(x_axis, i - 1), Enum.at(y_axis, i - 1), Enum.at(x_axis, k - 1), Enum.at(y_axis, k - 1), state.total_nodes) do
                    [k | acc]
                  else
                    acc
                  end
                end)
              :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{i}"}}, {:assigned_neighbors, neighbors})
            end)
        "torus" ->
          side = trunc(:math.sqrt(state.total_nodes))
          Enum.each(1..side,
            fn(i) ->
              Enum.each(1..side,
                fn(j) ->
                  neighbors =
                    [coordinate_2d_to_1d(i, rem(j, side) + 1, side)] ++  # right
                    [coordinate_2d_to_1d(i, rem(j + side - 2, side) + 1, side)] ++  # left
                    [coordinate_2d_to_1d(rem(i, side) + 1, j, side)] ++  # down
                    [coordinate_2d_to_1d(rem(i + side - 2, side) + 1, j, side)]  # up
                  :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{coordinate_2d_to_1d(i, j, side)}"}}, {:assigned_neighbors, neighbors})
                end)
            end)
        "line" ->
          line = Enum.shuffle(1..state.total_nodes)
          Enum.each(Enum.with_index(line),
          fn(x) ->
            neighbors =
              cond do
                elem(x, 1) == 0 ->
                  [Enum.at(line, 1)]
                elem(x, 1) == state.total_nodes - 1 ->
                  [Enum.at(line, state.total_nodes - 2)]
                true ->
                  [Enum.at(line, elem(x, 1) - 1)] ++ [Enum.at(line, elem(x, 1) + 1)]
              end
            :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{elem(x, 0)}"}}, {:assigned_neighbors, neighbors})
          end)
        "imp2D" ->
          line = Enum.shuffle(1..state.total_nodes)
          Enum.each(Enum.with_index(line),
          fn(x) ->
            nodes_without_self = Enum.filter(line, fn(y) -> y != elem(x, 0) end)
            neighbors =
              cond do
                elem(x, 1) == 0 ->
                  [Enum.at(line, 1)] ++ [Enum.random(nodes_without_self)]
                elem(x, 1) == state.total_nodes - 1 ->
                  [Enum.at(line, state.total_nodes - 2)] ++ [Enum.random(nodes_without_self)]
                true ->
                  [Enum.at(line, elem(x, 1) - 1)] ++ [Enum.at(line, elem(x, 1) + 1)] ++ [Enum.random(nodes_without_self)]
              end
            :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{elem(x, 0)}"}}, {:assigned_neighbors, neighbors})
          end)
      end
    end
  end

  defp rand2D_neighbor?(a_x, a_y, b_x, b_y, total_nodes) do
    if total_nodes <= 1000 do
      (a_x - b_x) * (a_x - b_x) + (a_y - b_y) * (a_y - b_y) <= @rand2D_neighbor_distance_square
    else
      abs(a_x - b_x) + abs(a_y - b_y) <= @rand2D_neighbor_approx_distance
    end
  end

  defp coordinate_2d_to_1d(i, j, side), do: (i - 1) * side + j

  defp coordinate_3d_to_1d(i, j, k, side), do: trunc((i - 1) * :math.pow(side, 2) + (j - 1) * side + k)

  defp valid_3d_coordinate?(i, j, k, side), do: (i > 0 and i <= side) and (j > 0 and j <= side) and (k > 0 and k <= side)

  defp print_gossip_progress(state) do
    new_progress = trunc(state.participants_heard_count / state.total_nodes * 100)
    unless new_progress == state.progress, do: IO.write("\rProgress: [#{new_progress |> Integer.to_string() |> String.pad_leading(3)}%]")
    new_progress
  end

  defp terminate_participants(algo, total_nodes) do
    if algo == "gossip" do
      Enum.each(1..total_nodes, fn(x) -> :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{x}"}}, :stop_gossip) end)
    end
    :timer.sleep(500)
    Enum.each(1..total_nodes, fn(x) -> :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{x}"}}, :terminate) end)
  end

  defp countdown do
    :timer.sleep(5000)
    Process.send(GossipSimulator.Manager, :timesup, [])
  end
end
