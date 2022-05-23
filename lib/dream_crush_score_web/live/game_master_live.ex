defmodule DreamCrushScoreWeb.GameMasterLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Rooms
  alias DreamCrushScore.Room
  alias DreamCrushScoreWeb.HomeLive
  alias DreamCrushScore.Room.AddCrush
  alias DreamCrushScore.Room.Broadcast
  alias DreamCrushScore.GameSession

  def mount(_params, session, socket) do
    bound? = GameSession.mount(session[:__sid__])
    unless bound? do
      IO.warn "unbound GameSession in game-master!"
      IO.inspect(session)
    end

    connected? = Phoenix.LiveView.connected?(socket)
    join_code = if bound? do GameSession.get("join_code") else nil end

    if connected? && join_code do
      Broadcast.connect_game_master(join_code)
    else
      IO.inspect("Not connected: #{connected?}, join_code: #{join_code}")
    end

    room_info = Rooms.get_room(join_code)

    if room_info do
      socket = socket
        |> assign(:join_code, join_code)
        |> load_room(room_info)
        |> assign(:add_crush_form, AddCrush.changeset(%AddCrush{}, %{name: ""}))
        |> assign(:joined, true)
      {:ok, socket}
    else
      Process.send_after(self(), :go_home, 5000)
      Process.send_after(self(), {:dec_seconds, 5}, 1000)
      if bound? do
        GameSession.put("join_code", false)
        GameSession.put("role", false)
      end
      socket = socket
      |> assign(:join_code, "")
      |> assign(:joined, false)
      |> assign(:seconds, 5)
      {:ok, socket}
    end
  end

  defp load_room(socket, room) do
    socket
      |> assign(:players, Room.joined_players(room))
      |> assign(:crushes, Room.crushes(room))
      |> assign(:game_state, Room.game_state(room))
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("add-crush", args, socket) do
    Rooms.add_crush(socket.assigns.join_code, args["add_crush"]["name"])
    {:noreply, assign(socket, :add_crush_form, AddCrush.changeset(%AddCrush{}, %{}))}
  end

  def handle_event("kick-player", args, socket) do
    IO.inspect(socket.assigns.join_code)
    Rooms.kick_player(socket.assigns.join_code, args["player-id"])
    {:noreply, socket}
  end

  def handle_event("start-round", _args, socket) do
    Rooms.start_round(socket.assigns.join_code)
    {:noreply, socket}
  end

  def handle_info(:clean_path, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__), replace: true)}
  end

  def handle_info({:dec_seconds, seconds}, socket) do
    Process.send_after(self(), {:dec_seconds, seconds - 1}, 1000)
    {:noreply, assign(socket, :seconds, seconds - 1)}
  end

  def handle_info({:players_updated, players}, socket) do
    IO.inspect("GM sees: #{inspect(players, pretty: true)}")
    socket = socket
    |> assign(:players, players)
    {:noreply, socket}
  end

  def handle_info({:crushes_updated, new_crushes}, socket) do
    {:noreply, assign(socket, :crushes, new_crushes)}
  end

  def handle_info({:live_session_updated, session}, socket) do
    socket = assign(socket, :join_code, session["join_code"])
    {:noreply, socket}
  end

  def handle_info({:start_round, room}, socket) do
    if socket.assigns[:game_state] in [:starting, :end_round] do
      {:noreply, load_room(socket, room)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:go_home, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, HomeLive, clear_token: "join_code"))}
  end
end
