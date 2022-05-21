defmodule DreamCrushScore.Player do
  @enforce_keys [:name, :id, :status]
  defstruct [:id, :name, :status, picks: [], pick_history: []]

  def set_status(%__MODULE__{} = player, new_status) when new_status == :awake or new_status == :asleep do
    Map.put(player, :status, new_status)
  end
  def set_picks(%__MODULE__{} = player, picks) do
    Map.put(player, :picks, picks)
  end

  def save_picks(%__MODULE__{picks: picks, pick_history: history } = player) do
    Map.put(player, :pick_history, Enum.concat(history, [picks]))
  end
end

defmodule DreamCrushScore.Room do

  # state: can be :starting, :in_round, :end_round, or :end_game
  defstruct [players: [], crushes: [], id: "", state: :starting]
  alias DreamCrushScore.Player

  def join(%__MODULE__{state: state, players: users} = room, %Player{}=user) do

    case state do
      :starting -> %{room | players: Enum.concat(users, [user])}
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
    state |> Map.put(:state, :in_round)
  end

  def set_player_picks(%__MODULE__{} = state, player_id, picks) do
    player = Map.get(state.players, player_id)
    if player do
      player = Player.set_picks(player, picks)
      put_in(state, [:players, player_id], player)
    else
      state
    end
  end

  def kick_player(%__MODULE__{players: players} = state, id) do
    Map.put(state, :players, Enum.filter(players, fn(p) -> p.id !== id end))
  end

  def joined_players(%__MODULE__{players: players}) do
    Enum.map(players, fn(p) -> %{ name: p.name, id: p.id, status: p.status } end)
  end

  def other_players(players, me_id) do
    players
    |> Enum.filter(fn p -> p.id !== me_id end)
    |> Enum.map(fn(p) -> %{ name: p.name, id: p.id, status: p.status } end)
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
  end

  def mark_player_awake(%__MODULE__{players: players} = state, id) do
    players = players
    |> Enum.map(fn p ->
      case p.id do
        ^id -> Player.set_status(p, :awake)
        _ -> p end
      end)
    Map.put(state, :players, players)
  end

  def add_crush(%__MODULE__{state: state, crushes: crushes} = room, crush)
    when is_binary(crush)
    when state !== :in_round do
    unless Enum.any?(crushes, fn(c) -> c == crush end) do
      %{room | crushes: Enum.concat(crushes, [crush])}
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
  alias DreamCrushScore.Player
  alias Phoenix.PubSub
  alias DreamCrushScore.PubSub, as: MyPubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{
      rooms: %{},
      players: %{}
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
    {status, players, new_player_id} = GenServer.call(__MODULE__, {:player_join, join_code, name})
    case status do
      :ok ->
        PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, players})
        {:ok, new_player_id}
      :full_room ->
        {:error, "The room is already full!"}
      :room_does_not_exist ->
        {:error, "Room does not exist"}
    end
  end

  def player_reconnect(join_code, id) when is_binary(join_code) and is_binary(id) do
    case GenServer.call(__MODULE__, {:player_reconnect, self(), join_code, id}) do
     {player, room} ->
        PubSub.subscribe(MyPubSub, topic_of_room(join_code))
        PubSub.subscribe(MyPubSub, topic_of_player_id(id))
        {player, room}
      _ -> nil
    end
  end

  def kick_player(join_code, id) when is_binary(join_code) and is_binary(id) do
    GenServer.cast(__MODULE__, {:kick_player, join_code, id})
  end

  def add_crush(join_code, id) do
    GenServer.call(__MODULE__, {:add_crush, join_code, id})
  end

  def start_round(join_code) do
    GenServer.cast(__MODULE__, {:start_round, join_code})
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
    state = put_in(state.rooms[join_code], %Room{})
    {:reply, join_code, state}
  end

  @impl true
  def handle_call({:add_crush, join_code, name},_from, state ) do

    state = update_in(state.rooms[join_code], &Room.add_crush(&1, name))
    room = state.rooms[join_code]
    PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:crushes_updated, Room.crushes(room)})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:player_reconnect, caller, join_code, player_id}, _from, state) do
    with %{ rooms: rooms, players: players } <- state,
         {:ok, room} <- fetch_code(rooms, join_code, :no_room),
         player when not(player === :invalid_player) <- Room.get_player(room, player_id) || :invalid_player
    do
      ref = Process.monitor(caller)

      state = state
      |> update_in([:rooms, join_code], &Room.mark_player_awake(&1, player_id))
      |> put_in([:players, ref], {join_code, player_id})
      players = state.rooms[join_code] |> Room.joined_players()

      PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, players})
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

    PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, Room.joined_players(room)})
    PubSub.broadcast(MyPubSub, topic_of_player_id(player_id), :kicked)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:start_round, join_code}, state) do
    room = state.rooms[join_code]
    state = state
      |> update_in([:rooms, join_code], &Room.start_round(&1))

    PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:start_round, room})
    {:noreply, state}
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
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {join_code, player_id} = state.players[ref]

    state = state
      |> update_in([:rooms, join_code], &Room.mark_player_asleep(&1, player_id))
      |> update_in([:players], &Map.delete(&1, ref))

    PubSub.broadcast(
      MyPubSub,
      topic_of_room(join_code),
      {:players_updated, Room.joined_players(state.rooms[join_code])}
    )

    {:noreply, state}
  end

  @alphabet 'ABCDEFGHIJKLMNOPLMNOPQRSTUVWXYZ1234567890'

  defp make_code(n) do
    for _ <- 1..n, into: "", do: <<Enum.random(@alphabet)>>
  end

  def topic_of_room(join_code) do
    join_code <> ":room"
  end

  def topic_of_player_id(player_id) do
    player_id <> ":player"
  end
end
