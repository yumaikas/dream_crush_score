
defmodule DreamCrushScoreWeb.GamePlayerLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Rooms
  alias DreamCrushScoreWeb.HomeLive
  alias DreamCrushScore.GameSession

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

  def handle_info({:players_updated, _updated_players}, socket) do
    {:noreply, socket}
  end

  def handle_info({:crushes_updated, _updated_crushes}, socket) do
    IO.inspect("TODO: handle updated crushes!")
    {:noreply, socket}
  end

  def handle_info(:kicked, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, HomeLive) )}
  end

  def handle_info({:live_session_updated, session}, socket) do
    {:noreply, socket}
  end

end
