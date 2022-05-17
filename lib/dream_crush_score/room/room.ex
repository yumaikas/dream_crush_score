defmodule DreamCrushScore.Player do
  @enforce_keys [:name, :id, :status]
  defstruct [:id, :name, :status, picks: [], pick_history: []]

  def set_status(%__MODULE__{} = player, new_status) when new_status == :awake or new_status == :asleep do
    Map.put(player, :status, new_status)
  end

end

defmodule DreamCrushScore.Room do
  defstruct [players: [], crushes: [], id: ""]
  alias DreamCrushScore.Player

  def join(%__MODULE__{players: users} = room, %Player{}=user) do
    %{room | players: Enum.concat(users, [user])}
  end

  def get_player(%__MODULE__{players: players}, id) do
    Enum.find(players, fn(p) -> p.id == id end)
  end

  def kick_player(%__MODULE__{players: players} = state, id) do
    Map.put(state, players, Enum.filter(players, fn(p) -> p.id !== id end))
  end

  def joined_players(%__MODULE__{players: players}) do
    IO.inspect(players)
    Enum.map(players, fn(p) -> %{ name: p.name, id: p.id, status: p.status } end)
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

  def add_crush(%__MODULE__{crushes: crushes} = room, crush) when is_binary(crush) do
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


  @spec player_join(binary, binary) :: {:error, nil} | {:ok, any}
  def player_join(join_code, name) when is_binary(join_code) and is_binary(name) do
    {ok?, players, new_player_id} = GenServer.call(__MODULE__, {:player_join, join_code, name})
    if ok? == :ok do
      PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, players})
      {:ok, new_player_id}
    else
      {:error, nil}
    end
  end

  def player_reconnect(join_code, id) when is_binary(join_code) and is_binary(id) do
    GenServer.call(__MODULE__, {:player_reconnect, self(), join_code, id})
  end

  def kick_player(join_code, id) do
    GenServer.cast(__MODULE__, {:kick_player, join_code, id})
  end

  @impl true
  def handle_cast({:kick_player, join_code, player_id}, state) do
    %{ rooms: %{^join_code => room} = rooms } = state
    state = %{state | rooms: %{ rooms | join_code => Room.kick_player(room, player_id)}}
    room = state.rooms[join_code]

    PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, Room.joined_players(room)})
    PubSub.broadcast(MyPubSub, topic_of_player_id(player_id), {:kicked})

    {:noreply, state}
  end

  @impl true
  def handle_call({:player_join, join_code, name}, {caller, _tag}, state) do
    room = state.rooms[join_code]
    player_id = make_code(8)
    if room do
      player = %Player{name: name, id: player_id, status: :live}
      room = Room.join(room, player)
      ref = Process.monitor(caller)
      state = state
      |> put_in([:rooms, join_code], room)
      |> put_in([:players, ref], {join_code, player_id})

      {:reply, {:ok, Room.joined_players(room), player_id}, state }
    else
      {:reply, {:error, nil, nil}, state}
    end
  end

  def handle_call({:get_room, join_code}, _from, state) do
    {:reply, state.rooms[join_code], state}
  end

  def handle_call({:create_room}, _from, state) do
    join_code = make_code(4)
    state = Map.put(state, :rooms, Map.put(state.rooms, join_code, %Room{}))
    {:reply, join_code, state}
  end

  @impl true
  def handle_call({:player_reconnect, caller, join_code, player_id}, _from, state) do
    %{
      rooms: %{ ^join_code => room} = rooms,
      players: players
    } = state
    ref = Process.monitor(caller)
    players = Map.put(players, ref, {join_code, player_id})
    room = Room.mark_player_awake(room, player_id)
    rooms = Map.put(rooms, join_code, room)
    state = state
    |> Map.put(:rooms, rooms)
    |> Map.put(:players, players)

    PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, Room.joined_players(room)})

    {:reply, Room.get_player(room, player_id), state}
  end


  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {join_code, player_id} = state.players[ref]

    room = state.rooms[join_code]
    room = Room.mark_player_asleep(room, player_id)
    rooms = Map.put(state.rooms, join_code, room)
    players = Map.delete(state.players, ref)

    state = state
    |> Map.put(:rooms, rooms)
    |> Map.put(:players, players)
    PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, Room.joined_players(room)})

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
