defmodule GossipSimulator.Participant do
  use GenServer

  @gossip_delay_range 100

  # Client

  def start_link(arg) do
    name = {:via, Registry, {GossipSimulator.Registry, "participant_#{Enum.at(arg, 1)}"}}
    GenServer.start_link(__MODULE__, arg |> Enum.at(0) |> Map.merge(%{self_id: Enum.at(arg, 1), self_name: "participant_#{Enum.at(arg, 1)}"}), name: name)
  end

  # Server (callbacks)

  def init(arg) do
    fail_node =
      if arg.fail_mode and Enum.random(1..100) <= arg.fail_rate, do: true, else: false

    state =
      case arg.algo do
        "gossip" ->
          Map.merge(arg, %{heard_gossip: false, gossiping: true, fail_node: fail_node, heard_gossip_count: 0, gossip_content: ""})
        "push-sum" ->
          Map.merge(arg, %{s: arg.self_id, w: 1.0, pushing: true, fail_node: fail_node, consecutive_small_change: 0})
      end
    {:ok, state}
  end

  def handle_call({:assigned_neighbors, neighbors}, _from, state) do
    new_state = Map.merge(state, %{neighbors: neighbors, neighbors_count: length(neighbors)})
    {:reply, :ok, new_state}
  end

  def handle_call(:terminate, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:gossip, content}, from, state) do
    GenServer.reply(from, :ok)

    if content == GossipSimulator.Manager.gossip_content() do
      new_state = Map.put(state, :heard_gossip_count, state.heard_gossip_count + 1)

      new_state =
        if new_state.gossiping and stop_gossip?(new_state) do
          Map.put(new_state, :gossiping, false)
        else
          new_state
        end

      new_state =
        unless new_state.heard_gossip do
          :ok = GenServer.call(GossipSimulator.Manager, {:heard_gossip, new_state.self_name}, :infinity)
          unless new_state.neighbors_count == 0 do
            Process.send_after(self(), :send_gossip, Enum.random(1..@gossip_delay_range))
            Map.merge(new_state, %{heard_gossip: true, gossip_content: content})
          else
            new_state
          end
        else
          new_state
        end

      {:noreply, new_state}
    end
  end

  def handle_call(:stop_gossip, _from, state) do
    new_state = Map.put(state, :gossiping, false)
    {:reply, :ok, new_state}
  end

  def handle_call(:start_push, from, state) do
    GenServer.reply(from, :ok)
    new_state =
      cond do
        state.fail_node ->
          :ok = GenServer.call(GossipSimulator.Manager, {:stop_pushing, :fail_node, state.self_id})
          state
        state.neighbors_count == 0 ->
          :ok = GenServer.call(GossipSimulator.Manager, {:stop_pushing, :no_neighbor, state.self_id})
          state
        true ->
          push_sum(state)
          Map.merge(state, %{s: state.s / 2, w: state.w / 2})
      end
    {:noreply, new_state}
  end

  def handle_call({:sum, s, w}, from, state) do
    GenServer.reply(from, :ok)
    GenServer.cast(GossipSimulator.Manager, :receive_sum)

    new_state =
      if small_change?(state.s, state.w, state.s + s, state.w + w) do
        Map.put(state, :consecutive_small_change, state.consecutive_small_change + 1)
      else
        Map.put(state, :consecutive_small_change, 0)
      end

    new_state = Map.merge(new_state, %{s: new_state.s + s, w: new_state.w + w})

    new_state =
      if stop_pushing?(new_state), do: Map.put(new_state, :pushing, false), else: new_state

    new_state =
      cond do
        new_state.fail_node ->
          :ok = GenServer.call(GossipSimulator.Manager, {:stop_pushing, :fail_node, new_state.s / new_state.w})
          new_state
        new_state.neighbors_count == 0 ->
          :ok = GenServer.call(GossipSimulator.Manager, {:stop_pushing, :no_neighbor, new_state.s / new_state.w})
          new_state
        not new_state.pushing ->
          :ok = GenServer.call(GossipSimulator.Manager, {:stop_pushing, :stopped, new_state.s / new_state.w})
          new_state
        true ->
          push_sum(new_state)
          Map.merge(new_state, %{s: new_state.s / 2, w: new_state.w / 2})
      end

    {:noreply, new_state}
  end

  def handle_info(:send_gossip, state) do
    if state.gossiping and not state.fail_node do
      spawn_link(fn() -> gossip(state.neighbors, state.neighbors_count) end)
      Process.send_after(self(), :send_gossip, Enum.random(1..@gossip_delay_range))
    end
    {:noreply, state}
  end

  # Aux

  defp gossip(neighbors, neighbors_count) do
    :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{Enum.at(neighbors, Enum.random(0..neighbors_count - 1))}"}}, {:gossip, GossipSimulator.Manager.gossip_content()}, :infinity)
  end

  defp stop_gossip?(state), do: state.heard_gossip_count >= 10

  defp push_sum(state), do: :ok = GenServer.call({:via, Registry, {GossipSimulator.Registry, "participant_#{Enum.random(state.neighbors)}"}}, {:sum, state.s / 2, state.w / 2})

  defp stop_pushing?(state), do: state.consecutive_small_change >= 3

  defp small_change?(prev_s, prev_w, s, w), do: abs(prev_s / prev_w - s / w) <= 1.0e-10
end
