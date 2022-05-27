defmodule DreamCrushScore.Player do
  @enforce_keys [:name, :id, :status]
  defstruct [:id, :name, :status, picks: %{}, pick_history: []]

  def set_status(%__MODULE__{} = player, new_status) when new_status == :awake or new_status == :asleep do
    Map.put(player, :status, new_status)
  end
  def set_picks(%__MODULE__{} = player, picks) do
    Map.put(player, :picks, picks)
  end

  def has_picks?(%__MODULE__{picks: picks}) do
    map_size(picks) > 0
  end

  def total_score(%__MODULE__{pick_history: history}) do
    Enum.reduce(history, 0, fn ({round, _, _}, score) -> score + round end)
  end

  def previous_pick(%__MODULE__{pick_history: history }) do
    {_, pick, _} = List.last(history)
    pick
  end

  def previous_pick_for(%__MODULE__{pick_history: history }, player_id) do
    {_, _, picks} = List.last(history)
    picks[player_id]
  end

  def finish_round(%__MODULE__{pick_history: history } = player, {score, choice, round_picks}) do
    player
    |> Map.put(:pick_history, Enum.concat(history, [{score, choice, round_picks}]))
    |> Map.put(:picks, %{})
  end
end

defmodule DreamCrushScore.Room do
  @enforce_keys [:join_code, :last_interact_time]
  defstruct [:join_code, :last_interact_time, players: [], crushes: [], state: :starting]
  # state: can be :starting, :in_round, :end_round, or :end_game
  alias DreamCrushScore.Player

  defp mark_interaction(%__MODULE__{}= state) do
    Map.put(state, :last_interact_time, System.monotonic_time(:second))
  end

  def join(%__MODULE__{state: state, players: users} = room, %Player{}=user) do
    case state do
      :starting ->
        %{room | players: Enum.concat(users, [user])}
        |> mark_interaction()
      _ -> room
    end
  end

  def get_player(%__MODULE__{players: players}, id) do
    Enum.find(players, fn(p) -> p.id == id end)
  end

  def game_state(%__MODULE__{state: state}) do
    state
  end

  def start_round(%__MODULE__{} = state) do
    state
    |> Map.put(:state, :in_round)
    |> mark_interaction()
  end

  def end_round_ready?(%__MODULE__{players: players}) do
    Enum.all?(players, &Player.has_picks?/1)
  end

  def end_round(%__MODULE__{} = state) do
    if end_round_ready?(state) do
      do_end_round(state)
      |> mark_interaction()
    else
      state
    end
  end

  defp do_end_round(%__MODULE__{players: players} = state) do
    pickmap = for p <- players, into: %{} do
      {p.id, p.picks["self"]}
    end
    crush_set = MapSet.new(Enum.map(players, &(&1.picks["self"])))

    point_map = for me <- players, into: %{} do
      correct? = fn (p_id) -> pickmap[p_id] == me.picks[p_id] end
      {player_score, history} =
        for p <- players, p.id !== me.id, reduce: {0, %{}} do
          {score, history} -> {
              if(correct?.(p.id), do: score + 1, else: score),
              Map.put(history, p.id, correct?.(p.id))
          }
        end
      {me.id, {player_score, me.picks["self"], history}}
    end

    state
    |> Map.put(:state, :round_end)
    |> Map.update!(:players, fn players ->
      Enum.map(players, fn p -> Player.finish_round(p, point_map[p.id]) end)
    end)
    |> Map.update!(:crushes, fn crushes ->
      Enum.filter(crushes, &MapSet.member?(crush_set, &1))
    end)
  end

  def scoreboard(%__MODULE__{players: players}) do
    player_map = for p <- players, into: %{} do
      {p.id, p}
    end

    players
    |> Enum.sort_by(&{Player.total_score(&1), &1.name}, :desc)
    |> Enum.map(fn p -> score_line(p, player_map) end)
  end

  defp score_line(player, player_map) do
    round_pick = Player.previous_pick(player)
    %{
      score: Player.total_score(player),
      name: player.name,
      choice: round_pick,
      guesses: for op <- Map.values(player_map), op.id !== player.id do
        op_choice = Player.previous_pick(op)
        %{
         name: op.name,
         id: op.id,
         correct: Player.previous_pick_for(op, player.id),
         chose: op_choice
        }
      end
    }
  end


  # Ensure that we're not saving picks that don't have everyone chosen
  defp validate_picks(%__MODULE__{} = room, player_id, picks) do
    players = joined_players(room)
      |> Enum.filter(fn p -> p.id !== player_id end)
    Enum.all?(players, fn p -> Map.has_key?(picks, p.id) end) and Map.has_key?(picks, "self")
  end

  def set_player_picks(%__MODULE__{} = room, player_id, picks) do
    if validate_picks(room, player_id, picks) do
      update_in(room.players,
        fn players -> Enum.map(players,
          fn p ->
            cond do
              p.id == player_id -> Player.set_picks(p, picks)
              true -> p
            end
        end)
      end)
      |> mark_interaction()
    else
      room
    end
  end

  def kick_player(%__MODULE__{players: players} = state, id) do
    Map.put(state, :players, Enum.filter(players, fn(p) -> p.id !== id end))
    |> mark_interaction()
  end

  defp players_for_broadcast(players) do
    Enum.map(players, fn(p) -> %{ name: p.name, id: p.id, status: p.status, has_picks: Player.has_picks?(p) } end)
  end

  def joined_players(%__MODULE__{players: players}) do
    players_for_broadcast(players)
  end

  def other_players(players, me_id) do
    players
    |> Enum.filter(fn p -> p.id !== me_id end)
    |> Enum.map(fn(p) -> %{ name: p.name, id: p.id, status: p.status, has_picks: p.has_picks } end)
  end

  def crushes(%__MODULE__{crushes: crushes}) do
    crushes
  end

  def in_round?(%__MODULE__{state: state}) do
    state === :in_round
  end

  def can_join?(%__MODULE__{state: state, players: players}) do
    length(players) > 6 or state !== :starting
  end

  def mark_player_asleep(%__MODULE__{players: players} = state, id) do
    players = players
    |> Enum.map(fn p ->
      case p.id do
        ^id -> Player.set_status(p, :asleep)
      _ -> p end
      end)
    Map.put(state, :players, players)
    |> mark_interaction()
  end

  def mark_player_awake(%__MODULE__{players: players} = state, id) do
    players = players
    |> Enum.map(fn p ->
      case p.id do
        ^id -> Player.set_status(p, :awake)
        _ -> p end
      end)
    Map.put(state, :players, players)
    |> mark_interaction()
  end

  def add_crush(%__MODULE__{state: state, crushes: crushes} = room, crush)
    when is_binary(crush)
    when state !== :in_round do
    unless Enum.any?(crushes, fn(c) -> c == crush end) do
      %{room | crushes: Enum.concat(crushes, [crush])}
      |> mark_interaction()
    else
      room
    end
  end

  def rename_crush(%__MODULE__{crushes: crushes} = room, old, new) when is_binary(old) and is_binary(new) do
    %{room | crushes: Enum.map(crushes, fn(c) ->
        if c == old do new else c end
    end)}
  end
end

defmodule DreamCrushScore.Rooms do
  use GenServer
  alias DreamCrushScore.Room
  alias DreamCrushScore.Room.Broadcast
  alias DreamCrushScore.Player

  def start_link(_opts) do
    Process.send_after(__MODULE__, :sweep, 60_000)
    GenServer.start_link(__MODULE__, %{
      rooms: %{},
      players: %{},
      timers: %{} # Dict<join_code, timer_ref[]>
    }, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  def create_room() do
    GenServer.call(__MODULE__, {:create_room})
  end

  def get_room(join_code) do
    GenServer.call(__MODULE__, {:get_room, join_code})
  end

  def player_join(join_code, name) when is_binary(join_code) and is_binary(name) do
    {status, _players, new_player_id} = GenServer.call(__MODULE__, {:player_join, join_code, name})
    case status do
      :ok -> {:ok, new_player_id}
      :full_room ->
        {:error, "The room is already full!"}
      :room_does_not_exist ->
        {:error, "Room does not exist"}
    end
  end

  def end_round(join_code) when is_binary(join_code) do
    case GenServer.call(__MODULE__, {:end_round, join_code}) do
      :ok -> :ok
      :unready -> :unready
      {:error, message} -> {:error, message}
    end
  end

  def player_reconnect(join_code, player_id) when is_binary(join_code) and is_binary(player_id) do
    case GenServer.call(__MODULE__, {:player_reconnect, self(), join_code, player_id}) do
     {player, room} ->
        Broadcast.connect_player(room, player_id)
        {player, room}
      _ -> nil
    end
  end

  def kick_player(join_code, id) when is_binary(join_code) and is_binary(id) do
    GenServer.cast(__MODULE__, {:kick_player, join_code, id})
  end

  def kill_room(join_code) do
    GenServer.cast(__MODULE__, {:kill_room, join_code})
  end

  def add_crush(join_code, id) do
    GenServer.call(__MODULE__, {:add_crush, join_code, id})
  end

  def start_round(join_code) do
    GenServer.cast(__MODULE__, {:start_round, join_code})
  end

  def save_player_picks(join_code, player_id, picks) do
    GenServer.call(__MODULE__, {:save_player_picks, join_code, player_id, picks})
  end

  @impl true
  def handle_call({:player_join, join_code, name}, {caller, _tag}, state) do
    room = state.rooms[join_code]
    player_id = make_code(8)
    cond do
      room && !Room.can_join?(room) ->
        player = %Player{name: name, id: player_id, status: :live}
        ref = Process.monitor(caller)
        state = state
        |> update_in([:rooms, join_code], &Room.join(&1, player))
        |> put_in([:players, ref], {join_code, player_id})
        Broadcast.updated_players(room)
        {:reply, {:ok, Room.joined_players(room), player_id}, state }
      room && Room.can_join?(room) ->
        {:reply, {:full_room, nil, nil}, state}
      true ->
        {:reply, {:room_does_not_exist, nil, nil}, state}
    end
  end

  @impl true
  def handle_call({:get_room, join_code}, _from, state) do
    {:reply, state.rooms[join_code], state}
  end

  @impl true
  def handle_call({:create_room}, _from, state) do
    join_code = make_code(4)
    state = put_in(state.rooms[join_code],
      %Room{
        join_code: join_code,
        last_interact_time: System.monotonic_time(:second)
      })
    {:reply, join_code, state}
  end

  @impl true
  def handle_call({:add_crush, join_code, name},_from, state ) do

    state = update_in(state.rooms[join_code], &Room.add_crush(&1, name))
    Broadcast.updated_crushes(state.rooms[join_code])

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:save_player_picks, join_code, player_id, picks}, _from, state) do
    with %{ rooms: rooms } <- state,
         {:ok, room} <- fetch_code(rooms, join_code, :no_room),
         player when not(player === :invalid_player) <- Room.get_player(room, player_id) || :invalid_player
    do
      state = update_in(state.rooms[join_code], &Room.set_player_picks(&1, player_id, picks))
      # TODO: Overbroadcasting a bit here.
      Broadcast.updated_players(state.rooms[join_code])
      {:reply, :ok, state}
    else
      err ->
        IO.inspect err
        {:reply, {:error, "Unable to save because #{err}"}, state}
    end
  end

  @impl true
  def handle_call({:end_round, join_code}, _from, state) do
    with %{ rooms: rooms, players: %{} } <- state,
         {:ok, room} <- fetch_code(rooms, join_code, :no_room),
         true <- Room.end_round_ready?(room) || :unready
    do
      state = update_in(state, [:rooms, join_code], &Room.end_round(&1))
      room = state.rooms[join_code]
      IO.inspect Room.scoreboard(state.rooms[join_code])
      timers = for {line, idx} <- Room.scoreboard(room) |> Enum.with_index() do
        IO.inspect line
        Process.send_after(__MODULE__, {:broadcast_score_line, room, line}, 7500 * idx)
      end
      state = put_in(state, [:timers, join_code], timers)
      {:reply, :ok, state}
    else
      :unready -> {:reply, :unready, state}
      other -> {:reply, {:error, other}, state}
    end
  end

  @impl true
  def handle_call({:player_reconnect, caller, join_code, player_id}, _from, state) do
    with %{ rooms: rooms, players: %{} } <- state,
         {:ok, room} <- fetch_code(rooms, join_code, :no_room),
         player when not(player === :invalid_player) <- Room.get_player(room, player_id) || :invalid_player
    do
      ref = Process.monitor(caller)

      state = state
      |> update_in([:rooms, join_code], &Room.mark_player_awake(&1, player_id))
      |> put_in([:players, ref], {join_code, player_id})
      Broadcast.updated_players(state.rooms[join_code])

      {:reply, {player, room}, state}
    else
      err ->
        IO.inspect err
        {:reply, nil, state}
    end
  end

  @impl true
  def handle_cast({:kick_player, join_code, player_id}, state) do
    state = update_in(state.rooms[join_code], &Room.kick_player(&1, player_id))
    room = state.rooms[join_code]
    Broadcast.kicked_player(room, player_id)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:kill_room, join_code}, state) do
    with %{ rooms: rooms, players: %{} } <- state,
      {:ok, room} <- MapEx.fetch_code(rooms, join_code, :no_room)
    do
      for p <- Room.joined_players(room) do
        Broadcast.kicked_player(room, p.id)
      end
      state = update_in(state.rooms, &Map.delete(&1, join_code))
      {:noreply, state}
    else
      _ -> {:noreply, state}
    end

  end


  @impl true
  def handle_cast({:start_round, join_code}, state) do
    {:noreply, do_start_round(state, join_code)}
  end

  def do_start_round(state, join_code) do
    state = update_in(state,[:rooms, join_code], &Room.start_round(&1))
    Broadcast.start_round(state.rooms[join_code])
    state
  end

  defp fetch_code(map, key, code) do
    value = Map.get(map, key, nil)
    if !value do
      code
    else
      {:ok, value}
    end
  end

  @impl true
  def handle_info({:broadcast_score_line, %Room{join_code: join_code} = room, line}, state) do
    state = update_in(state.timers[join_code], &Enum.filter(&1, fn t_ref -> Process.read_timer(t_ref) end))
    Broadcast.show_score_line(room, line)

    if length(state.timers[join_code]) === 0 do
      Process.send_after(__MODULE__, {:show_end_round, room}, 7_500)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:show_end_round, %Room{join_code: join_code} = room}, state) do
    Broadcast.show_end_round(room)
    Process.send_after(__MODULE__, {:start_round, join_code}, 10_000)
    {:noreply, state}
  end

  @impl true
  def handle_info({:start_round, join_code}, state) do
    {:noreply, do_start_round(state, join_code)}
  end


  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {join_code, player_id} = state.players[ref]

    state = if state.rooms[join_code] do
      state = state
        |> update_in([:rooms, join_code], &Room.mark_player_asleep(&1, player_id))
        |> update_in([:players], &Map.delete(&1, ref))
      Broadcast.updated_players(state.rooms[join_code])
      state
    else
      state
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    state = update_in(state.rooms, fn rooms ->
      now = System.monotonic_time(:second)
      for {_, room} <- rooms, (now - room.last_interact_time) > (60 * 15) do
        for p <- Room.joined_players(room) do
          Broadcast.kicked_player(room, p.id)
        end
      end
      for {join_code, room} <- rooms, (now - room.last_interact_time) <= (60 * 15), into: %{} do
        {join_code, room}
      end
    end)
    {:noreply, state}
  end


  @alphabet 'ABCDEFGHIJKLMNOPLMNOPQRSTUVWXYZ1234567890'

  defp make_code(n) do
    for _ <- 1..n, into: "", do: <<Enum.random(@alphabet)>>
  end

end
