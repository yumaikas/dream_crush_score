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
    IO.inspect join_code
    socket = socket
    |> assign(join_form: Join.changeset(%Join{}, %{code: "", name: ""}))
    |> assign(join_code: join_code)

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
        PhoenixLiveSession.put_session(socket, "player_id", player_id)
        PhoenixLiveSession.put_session(socket, "join_code", code)
        socket = socket
        |> push_redirect(to: Routes.live_path(socket, GamePlayerLive))
        {:noreply, socket} # TODO: Redirect to player page
      :error ->
        join_form = socket.join_form
        join_form = join_form
        |> Ecto.Changeset.add_error(join_form, :code, "Invite code wasn't found!")
        socket = socket |> assign(:join_form, join_form)
        {:noreply, socket}
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

  @impl true
  def handle_info({:live_session_updated, session}, socket) do
    socket = assign(socket, :join_code, session["join_code"])
    {:noreply, socket}
  end

  def handle_info(:clean, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__))}
  end

end
