
defmodule DreamCrushScoreWeb.GamePlayerLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Rooms
  alias DreamCrushScore.Room
  alias DreamCrushScoreWeb.HomeLive
  alias DreamCrushScore.GameSession
  alias DreamCrushScore.Room.Broadcast

  def mount(_params, session, socket) do
    connected? = Phoenix.LiveView.connected?(socket)
    bound? = GameSession.mount(session[:__sid__])
    socket = socket |> PhoenixLiveSession.maybe_subscribe(session)

    if bound? do
      join_code = GameSession.get("join_code")
      player_id = GameSession.get("player_id")
      unless GameSession.get("role") === :player do
        {:ok, go_home(socket)}
      else
        if connected? do
          Broadcast.connect_player(join_code, player_id)
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

  defp start_round(socket, room, player_id) do
    GameSession.put(:picks, %{})
    socket
      |> assign(:picks, %{})
      |> load_round(room, player_id)
  end

  defp load_round(socket, room, player_id) do
    other_players = Room.joined_players(room) |> Room.other_players(player_id)
    socket
      |> assign(:picks, socket.assigns[:picks] || GameSession.get(:picks) || %{})
      |> assign(:game_state, :in_round)
      |> assign(:other_players, other_players)
      |> assign(:crushes, Room.crushes(room))
  end

  defp go_home(socket) do
      GameSession.put("join_code", nil)
      GameSession.put("player_id", nil)
      GameSession.put("role", nil)
      push_redirect(socket, to: Routes.live_path(socket, HomeLive))
  end

  defp join_room(socket, join_code, player_id) do
    case Rooms.player_reconnect(join_code, player_id) do
      {player, %Room{state: state} = room} when state === :in_round  ->
        socket
        |> assign(:join_code, join_code)
        |> assign(:name, player.name)
        |> assign(:player_id, player_id)
        |> load_round(room, player_id)
      {player, %Room{} = _room}  ->
        socket
        |> assign(:join_code, join_code)
        |> assign(:name, player.name)
        |> assign(:player_id, player_id)
      _ ->
        go_home(socket)
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def pick_crush_for_player(socket, crush, player_id) do
    pick_key = case player_id  do
      :self -> :my_pick
      id -> id
    end

    picks = GameSession.get(:picks) |> Map.put(pick_key, crush)

    other_players = MapSet.new(socket.assigns.players, &(&1.id))
    ready? = picks
      |> Map.keys()
      |> Enum.filter(&(&1 !== "self"))
      |> MapSet.new()
      |> tap(&IO.inspect("Picks: #{inspect(&1, pretty: true)}"))
      |> MapSet.equal?(other_players)
    IO.inspect("Picks: #{inspect(other_players, pretty: true)}")

    GameSession.put(:picks, picks)
    if ready? do
      %{join_code: join_code, player_id: player_id} = socket.assigns
      Rooms.save_player_picks(join_code, player_id, picks)
    end

    socket |> assign(:picks, picks)
  end

  def handle_event("pick-crush", %{"crush" => crush, "for" => player_id}, socket) do
    {:noreply, pick_crush_for_player(socket, crush, player_id) }
  end

  def handle_info({:players_updated, updated_players}, socket) do
    {:noreply, assign(socket, :players, Room.other_players(updated_players, socket.assigns.player_id)) }
  end

  def handle_info({:crushes_updated, updated_crushes}, socket) do
    {:noreply, assign(socket, :crushes, updated_crushes)}
  end

  def handle_info(:kicked, socket) do
    {:noreply, go_home(socket)}
  end

  def handle_info({:live_session_updated, _session}, socket) do
    {:noreply, socket}
  end

  def handle_info({:start_round, room}, socket) do
    {:noreply, start_round(socket, room, socket.assigns.player_id)}
  end

  def handle_info(:round_end, socket) do
    socket = socket
    |> assign(:game_state, {:end_round, :waiting})
    {:noreply, socket}
  end

  def handle_info({:show_score_line, score_line}, socket) do
    socket = socket
    |> assign(:game_state, {:end_round, :show_score_line, score_line})
    {:noreply, socket}
  end

  def handle_info({:show_end_round, scoreboard}, socket) do
    socket = socket
    |> assign(:game_state, {:end_round, :show_score_table, scoreboard})
    {:noreply, socket}
  end

  # Function components

  defp class_for(picks, player_id, crush) do
    case Map.get(picks, player_id) do
      ^crush -> ""
      _ -> "button-outline"
    end
  end

  def show_score_table(assigns) do
    ~H"""
    <h3>The scores at the end of the round are:</h3>
    <ul>
      <%= for line <- @score_lines do %>
        <li><%=line.name%> has <%=line.score%> points</li>
      <%end%>
    </ul>
    """
  end

  def show_score_line(assigns) do
    ~H"""
    <h3><%=@name%> chose <%=@choice%></h3>
    <%= for guess <- @guesses do %>
    <span><%=guess.name%>
      <%= if guess.correct do %>
        <span style="color: magenta;">✓</span>
      <% else %>
        <span style="color: red;">X</span>
      <% end %>
    </span>
    <% end %>
    """
  end

  def crush_picker(assigns) do
    ~H"""
    <p>
      <h4>Who would <%= @name %> pick?</h4>
      <%= for crush <- @crushes do %>
        <button phx-click="pick-crush" class={class_for(@picks, @for, crush)} phx-value-crush={crush} phx-value-for={@for}><%=crush%></button>
      <% end %>
    </p>
    """
  end

end
