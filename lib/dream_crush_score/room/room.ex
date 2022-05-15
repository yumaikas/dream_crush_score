defmodule DreamCrushScore.Player do
  @enforce_keys [:name]
  defstruct [:name, picks: [], pick_history: []]
end

defmodule DreamCrushScore.Room do
  defstruct [players: [], crushes: [], id: ""]
  alias DreamCrushScore.Player

  def join(%__MODULE__{players: users} = room, %Player{}=user) do
    %{room | players: Enum.concat(users, [user])}
  end

  def joined_players(%__MODULE__{players: players}) do
    Enum.map(players, fn(p) -> p.name end)
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
  use Agent
  alias DreamCrushScore.Room
  alias DreamCrushScore.Player
  alias Phoenix.PubSub
  alias DreamCrushScore.PubSub, as: MyPubSub

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def create_room() do
    join_code = make_code()
    Agent.update(__MODULE__, fn(state) -> Map.put(state, join_code, %Room{}) end)
    join_code
  end

  def get_room(join_code) do
    Agent.get(__MODULE__, fn(state) -> state[join_code] end)
  end

  def topic_of_room(join_code) do
    join_code <> ":room"
  end

  def player_join(join_code, name) when is_binary(join_code) and is_binary(name) do
    {ok?, players} = Agent.get_and_update(__MODULE__, fn(state) ->
      room = state[join_code]
      if room do
        room = Room.join(room, %Player{name: name})
        {{:ok, Room.joined_players(room)}, %{state | join_code => room}}
      else
        {{:error, nil}, state}
      end
      state
    end)
    if ok? == :ok do
      PubSub.broadcast(MyPubSub, topic_of_room(join_code), {:players_updated, players})
      :ok
    else
      :error
    end

  end


  @alphabet 'ABCDEFGHIJKLMNOPLMNOPQRSTUVWXYZ1234567890'

  defp make_code() do
    for _ <- 1..4, into: "", do: <<Enum.random(@alphabet)>>
  end


end
