
defmodule DreamCrushScoreWeb.GamePlayerLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Rooms
  alias DreamCrushScoreWeb.HomeLive
  alias DreamCrushScore.GameSession
  alias Phoenix.PubSub
  alias DreamCrushScore.PubSub, as: MyPubSub

  def mount(_params, session, socket) do
    connected? = Phoenix.LiveView.connected?(socket)
    bound? = GameSession.mount(session[:__sid__])
    socket = socket |> PhoenixLiveSession.maybe_subscribe(session)

    if bound? do
      join_code = GameSession.get("join_code")
      player_id = GameSession.get("player_id")
      unless GameSession.get("role") === :player do
        {:ok, push_redirect(socket, Routes.live_path(socket, HomeLive))}
      else
        if connected? do
          PubSub.subscribe(MyPubSub, Rooms.topic_of_room(join_code))
          PubSub.subscribe(MyPubSub, Rooms.topic_of_player_id(player_id))
        end

        socket = socket
        |> assign(:show_code, true)
        |> assign(:game_state, :setup)
        |> join_room(join_code, player_id)
        {:ok, socket}
      end
    else
      socket = socket
      |> assign(:game_state, :setup)
      |> assign(:show_code, false)
      {:ok, socket}
    end
  end

  defp join_room(socket, join_code, player_id) do
    player = Rooms.player_reconnect(join_code, player_id)

    if player do
      socket
      |> assign(:join_code, join_code)
      |> assign(:name, player.name)
      |> assign(:player_id, player_id)
    else
      push_redirect(socket, to: Routes.live_path(socket, HomeLive))
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_info({:players_updated, updated_players}, socket) do
    {:noreply, assign(socket, :players, updated_players) }
  end

  def handle_info({:crushes_updated, updated_crushes}, socket) do
    {:noreply, assign(socket, :crushes, updated_crushes)}
  end

  def handle_info(:kicked, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, HomeLive) )}
  end

  def handle_info({:live_session_updated, _session}, socket) do
    {:noreply, socket}
  end

end
