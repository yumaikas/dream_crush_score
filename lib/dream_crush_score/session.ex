defmodule MapEx do
  def fetch_code(map, key, code) do
    value = Map.get(map, key, nil)
    if !value do
      code
    else
      {:ok, value}
    end
  end
end

defmodule DreamCrushScore.GameSession do
  use GenServer
  # @TODO: Work on cleaning things up!

  @moduledoc """
  A GameSession server is based on the __sid__ provided by
  PhoenixLiveSession, and should repond to kicks by ending the session
  """

  @impl true
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{
      pidmap: %{}, # pid -> session,
      sessions: %{}, # sids -> dicts
      session_counts: %{} # sids -> counts
    }, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  def mount(session_id) do
    if session_id do
      GenServer.call(__MODULE__, {:mount, self(), session_id})
    else
    end
  end

  def get(key, default \\ nil) do
    case GenServer.call(__MODULE__, {:get, self(), key }) do
      {:ok, value} -> value || default
      :unmounted -> raise "Please ensure call GameSession.mount/1 before calling get!"
      :missing_session -> raise "This should _never_ happen!"
    end
  end


  def put(key, value) do
    case GenServer.call(__MODULE__, {:put, self(), key, value}) do
      :ok -> :ok
      :unmounted -> raise "Please ensure call GameSession.mount/1 before calling put!"
      :missing_session -> raise "This should _never_ happen!"
    end
  end

  defp reset_session(session_id, to) do
    GenServer.call(__MODULE__, {:reset_session, session_id, to})
  end

  @impl true
  def handle_call({:get, caller, key}, _from, state) do
    with {:ok, session_id} <- MapEx.fetch_code(state.pidmap, caller, :unmounted),
      {:ok, session} <- MapEx.fetch_code(state.sessions, session_id, :missing_session),
      value <- Map.get(session, key)
    do
      {:reply, {:ok, value}, state}
    else
      :unmounted -> {:reply, :unmounted, state}
      :missing_session -> {:reply, :missing_session, state }
    end
  end

  @impl true
  def handle_call({:put, caller, key, value}, _from, state) do
    with {:ok, session_id} <- MapEx.fetch_code(state.pidmap, caller, :unmounted),
      {:ok, session} <- MapEx.fetch_code(state.sessions, session_id, :missing_session),
      session = Map.put(session, key, value),
      sessions = Map.put(state.sessions, session_id, session),
      state = Map.put(state, :sessions, sessions)
    do
      {:reply, :ok, state}
    else
      :unmounted -> {:reply, :unmounted, state}
      :missing_session -> {:reply, :missing_session, state }
    end
  end

  @impl true
  def handle_call({:mount, caller, session_id}, _from, state) do
    %{
      pidmap: pidmap,
      sessions: sessions,
      session_counts: session_counts
    } = state
    sessions = Map.put_new(sessions, session_id, %{})
    Process.monitor(caller)
    session_counts = Map.update(session_counts, session_id, 1, &(&1 + 1))
    pidmap = Map.put_new(pidmap, caller, session_id)

    {
      :reply,
      :ok,
      state
        |> Map.put(:pidmap, pidmap)
        |> Map.put(:sessions, sessions)
        |> Map.put(:session_counts, session_counts)
     }
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    %{
      pidmap: pidmap,
      sessions: sessions,
      session_counts: session_counts
    } = state
    {session_id, pidmap} = Map.pop(pidmap, pid)
    session_counts = Map.update(session_counts, session_id, 0, &(&1 - 1))

    state = state
      |> Map.put(:pidmap, pidmap)
      |> Map.put(:sessions, sessions)
      |> Map.put(:session_counts, session_counts)
    {:noreply, state}
  end


end
