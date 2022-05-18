defmodule DreamCrushScoreWeb.HomeLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Room.Join
  alias DreamCrushScore.Rooms
  alias DreamCrushScore.GameSession
  alias DreamCrushScoreWeb.GameMasterLive
  alias DreamCrushScoreWeb.GamePlayerLive


  @impl true
  def mount(_params, session, socket) do
    bound? = GameSession.mount(session[:__sid__])
    socket = if Phoenix.LiveView.connected?(socket) do
      socket
      |> PhoenixLiveSession.maybe_subscribe(session)
    else
      socket
    end

    cond do
      bound? ->
        role = GameSession.get("role")
        join_code = GameSession.get("join_code")
        cond do
          role === :admin && join_code ->
            {:ok, push_redirect(socket, to: Routes.live_path(socket, GameMasterLive))} # TODO: Redirect to player page
          role === :player && join_code ->
            {:ok, push_redirect(socket, to: Routes.live_path(socket, GamePlayerLive))} # TODO: Redirect to player page
          true ->
            socket = socket
            |> assign(:join_form, Join.changeset(%Join{}, %{code: "", name: ""}))
            |> assign(:join_code, false)
            {:ok, socket}
        end
      true ->
        socket = socket
        |> assign(:join_form, Join.changeset(%Join{}, %{code: "", name: ""}))
        |> assign(:join_code, false)
        {:ok, socket}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("try_join_room", %{"join" => %{"code" => code, "name" => name}}, socket) do
    {status, player_id} = Rooms.player_join(code, name)
    case status do
      :ok ->
        GameSession.put("player_id", player_id)
        GameSession.put("join_code", code)
        GameSession.put("role", :player)
        {:noreply, push_redirect(socket, to: Routes.live_path(socket, GamePlayerLive))} # TODO: Redirect to player page
      :error ->
        {:noreply, put_flash(socket, :error, "Invite code wasn't found!")}
    end
  end

  @impl true
  def handle_event("rejoin_game", _args, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, GameMasterLive))}
  end

  @impl true
  def handle_event("create_room", _args, socket) do
    join_code = Rooms.create_room()
    GameSession.put("join_code", join_code)
    GameSession.put("role", :admin)
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, GameMasterLive))}
  end

  defp extract_session(socket) do
    {_sid, session} = PhoenixLiveSession.get(nil, Map.get(socket.assigns, :__sid__), Map.get(socket.assigns, :__opts__))
    session
  end

  defp check_redirect(kvs, to) do
      Process.send_after(self(), {:redirect_check, kvs, to}, 20)
  end

  def handle_info({:redirect_check, kvs, to}, socket) do
    session = extract_session(socket)
    all_found? = for {key, value} <- kvs do
      Map.get(session, key) === value || false
    end |> Enum.all?(fn e -> e end)
    IO.inspect session
    if all_found? do
      {:noreply, push_redirect(socket, to: to)}
    else
      check_redirect(kvs, to)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:live_session_updated, session}, socket) do
    socket = assign(socket, :join_code, session["join_code"])
    {:noreply, socket}
  end

  def handle_info(:clean, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__))}
  end

end
