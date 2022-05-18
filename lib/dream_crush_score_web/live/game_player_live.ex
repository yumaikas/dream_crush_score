
defmodule DreamCrushScoreWeb.GamePlayerLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Rooms
  alias DreamCrushScoreWeb.HomeLive

  def mount(_params, session, socket) do
    connected? = Phoenix.LiveView.connected?(socket)

    socket = if connected? do
      socket
      |> PhoenixLiveSession.maybe_subscribe(session)
    else
      socket
    end

    socket = if !Map.get(session, "join_code") || !Map.get(session, "player_id") do
      IO.inspect "waited"
      Process.send_after(self(), :check_session, 20)
      assign(socket, :join_code, "")
    else
      IO.inspect "immediate-join"
      IO.inspect session

      socket
      |> join_room(Map.get(session, "join_code"), Map.get(session, "player_id"))
      |> assign(:join_code, Map.get(session, "join_code"))
    end

    socket = socket
    |> assign(:game_state, :setup)
    |> assign(:show_code, true)
    |> assign(:__sid__, session[:__sid__])
    |> assign(:__opts__, session[:__opts__])
    {:ok, socket}
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

  defp get_session(socket, key, fallback \\ nil) do
    {_sid, session} = PhoenixLiveSession.get(nil, Map.get(socket.assigns, :__sid__), Map.get(socket.assigns, :__opts__))
    Map.get(session, key, fallback)
  end

  def handle_info({:players_updated, _updated_players}, socket) do
    {:noreply, socket}
  end

  def handle_info({:crushes_updated, _updated_crushes}, socket) do
    IO.inspect("TODO: handle updated crushes!")
    {:noreply, socket}
  end

  def handle_info(:check_session, socket) do
    connected? = Phoenix.LiveView.connected?(socket)
    socket = case {get_session(socket, "join_code"), get_session(socket, "player_id")} do
      {a, b} when is_nil(a) or is_nil(b) or not connected? ->
        Process.send_after(self(), :check_session, 20)
        socket
      {join_code, player_id} -> join_room(socket, join_code, player_id)
    end
    {:noreply, socket}
  end

  def handle_info(:kicked, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, HomeLive) )}
  end

  def handle_info({:live_session_updated, session}, socket) do
    socket = assign(socket, :join_code, session["join_code"])
    {:noreply, socket}
  end

end
