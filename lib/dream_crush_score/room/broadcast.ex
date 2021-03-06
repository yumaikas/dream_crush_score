defmodule DreamCrushScore.Room.Broadcast do
  alias DreamCrushScore.Room
  alias Phoenix.PubSub
  alias DreamCrushScore.PubSub, as: MyPubSub
  alias Phoenix.PubSub

  def connect_game_master(join_code) when is_binary(join_code) do
    PubSub.subscribe(MyPubSub, topic_of_room(join_code))
  end

  def disconnect_all(join_code) when is_binary(join_code) do
    PubSub.broadcast(MyPubSub, topic_of_room(join_code), :go_home)
  end

  def connect_player(%Room{join_code: join_code} = _room, player_id)  do
    PubSub.subscribe(MyPubSub, topic_of_room(join_code))
    PubSub.subscribe(MyPubSub, topic_of_player_id(player_id))
  end
  def connect_player(join_code, player_id) when is_binary(join_code) do
    PubSub.subscribe(MyPubSub, topic_of_room(join_code))
    PubSub.subscribe(MyPubSub, topic_of_player_id(player_id))
  end

  def updated_players(%Room{} = room)  do
    players = Room.joined_players(room)
    IO.inspect(players)
    IO.inspect("Broadcasting on #{topic_of_room(room)}")
    PubSub.broadcast(MyPubSub, topic_of_room(room), {:players_updated, players})
  end

  def updated_crushes(%Room{} = room) do
    PubSub.broadcast(MyPubSub, topic_of_room(room), {:crushes_updated, Room.crushes(room)})
  end

  def kicked_player(%Room{} = room, player_id) do
    PubSub.broadcast(MyPubSub, topic_of_room(room), {:players_updated, Room.joined_players(room)})
    PubSub.broadcast(MyPubSub, topic_of_player_id(player_id), :kicked)
  end

  def start_round(%Room{} = room) do
    PubSub.broadcast(MyPubSub, topic_of_room(room), {:start_round, room})
  end

  def show_score_line(%Room{} = room, %{} = score_line) do
    PubSub.broadcast(MyPubSub, topic_of_room(room), {:show_score_line, score_line})
  end

  def show_end_round(%Room{} = room) do
    PubSub.broadcast(MyPubSub, topic_of_room(room), {:show_end_round, Room.scoreboard(room)})
  end

  def topic_of_room(%Room{join_code: join_code}) do
    topic_of_room(join_code)
  end
  def topic_of_room(join_code) when is_binary(join_code) do
    join_code <> ":room"
  end

  def topic_of_player_id(player_id) do
    player_id <> ":player"
  end
end
