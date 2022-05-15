defmodule DreamCrushScoreWeb.GameMasterLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Rooms
  alias DreamCrushScore.Room
  alias DreamCrushScoreWeb.HomeLive
  alias Phoenix.PubSub
  alias DreamCrushScore.PubSub, as: MyPubSub

  def mount(params, session, socket) do
    join_code = params["join_code"] || session["join_code"]
    connected? = Phoenix.LiveView.connected?(socket)

    socket = if connected? do
      socket
      |> PhoenixLiveSession.maybe_subscribe(session)
      |> PhoenixLiveSession.put_session("join_code", join_code)
    else
      socket
    end
    if connected? && join_code do
      PubSub.subscribe(MyPubSub, Rooms.topic_of_room(join_code))
    end

    room_info = Rooms.get_room(join_code)
    if room_info do
      Process.send_after(self(), :clean_path, 1)
      socket = socket
        |> assign(:join_code, join_code)
        |> assign(:players, Room.joined_players(room_info))
        |> assign(:joined, true)
      {:ok, socket}
    else
      Process.send_after(self(), :go_home, 5000)
      Process.send_after(self(), {:dec_seconds, 5}, 1000)
      if connected? do
        PhoenixLiveSession.put_session(socket, "join_code", false)
      end
      socket = socket
      |> assign(:join_code, "")
      |> assign(:joined, false)
      |> assign(:seconds, 5)
      {:ok, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
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
    socket = socket
    |> assign(:players, players)
    {:noreply, socket}
  end

  def handle_info({:live_session_updated, session}, socket) do
    socket = assign(socket, :join_code, session["join_code"])
    {:noreply, socket}
  end

  def handle_info(:go_home, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, HomeLive, clear_token: "join_code"))}
  end
end
