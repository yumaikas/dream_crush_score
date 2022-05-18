defmodule DreamCrushScoreWeb.HomeLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Room.Join
  alias DreamCrushScore.Rooms
  alias DreamCrushScoreWeb.GameMasterLive
  alias DreamCrushScoreWeb.GamePlayerLive


  @impl true
  def mount(params, session, socket) do
    socket = if Phoenix.LiveView.connected?(socket) do
      socket
      |> PhoenixLiveSession.maybe_subscribe(session)
    else
      socket
    end

    join_code = unless params["clear_token"] do
       session["join_code"]
    else
       PhoenixLiveSession.put_session(socket, :join_code, false)
       Process.send_after(self(), :clean, 1)
       false
    end
    socket = socket
    |> assign(join_form: Join.changeset(%Join{}, %{code: "", name: ""}))
    |> assign(join_code: join_code)
    |> assign(:__sid__, session[:__sid__])
    |> assign(:__opts__, session[:__opts__])

    {:ok, socket}
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
        check_redirect(
          [{"player_id", player_id},
           {"join_code", code},
           {"role", :player}],
          Routes.live_path(socket, GamePlayerLive)
        )
        socket = socket
        |> PhoenixLiveSession.put_session("player_id", player_id)
        |> PhoenixLiveSession.put_session("join_code", code)
        |> PhoenixLiveSession.put_session("role", :player)
        {:noreply, socket} # TODO: Redirect to player page
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
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, GameMasterLive, join_code: join_code))}
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
