defmodule DreamCrushScore.GameSession do
  use GenServer

  @moduledoc """
  A GameSession server is based on the __sid__ provided by
  PhoenixLiveSession, and should repond to kicks by ending the session
  """

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{
      pidmap: %{},
      sessions: %{}
    }, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def mount(session) do
  end

end
