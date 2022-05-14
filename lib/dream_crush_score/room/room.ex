defmodule DreamCrushScore.Player do
  @enforce_keys [:name]
  defstruct [:name]
end

defmodule DreamCrushScore.Room do
  alias DreamCrushScore.Player
  defstruct [players: [], crushes: [], id: ""]

  def join(%__MODULE__{players: users} = room, %Player{}=user) do
    %{room | players: Enum.concat(users, [user])}
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

defmodule DreamCrushScore.Room.Process do
  use GenServer
  alias DreamCrushScore.Room
  alias DreamCrushScore.Player

  # CLient
  def start_link() do
    GenServer.start_link(__MODULE__, %DreamCrushScore.Room{})
  end

  # Server
  @impl true
  def init(%Room{} =room) do
    {:ok, room}
  end

  @impl true
  def handle_call({:join, %Player{}=player}, _from, room) do
    room = room |> Room.join(player)
    {:reply, :ok, room}
  end

  @impl true
  def handle_call({:rename_crush, old, new}, _from, room) do
    room = room |> Room.rename_crush(old, new)
    # TODO Broacast change?
    {:reply, :ok, room}
  end

end
