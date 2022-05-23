defmodule DreamCrushScore.Room.Tests do
  use ExUnit.Case
  alias DreamCrushScore.Room
  alias DreamCrushScore.Player

  @alphabet 'ABCDEFGHIJKLMNOPLMNOPQRSTUVWXYZ1234567890'

  defp make_code(n) do
    for _ <- 1..n, into: "", do: <<Enum.random(@alphabet)>>
  end


  setup do
    p1 = %Player{id: "ADELLE__", name: "Adelle", status: :live}
    p2 = %Player{id: "BILLY___", name: "Billy", status: :live}
    p3 = %Player{id: "CARSON__", name: "Carson", status: :live}
    p4 = %Player{id: "DELIA___", name: "Delia", status: :live}

    join_code = make_code(4)

    {:ok,
      players: %{ player1: p1, player2: p2, player3: p3, player4: p4},
      join_code: join_code
    }
  end

  defp build_room(players, join_code) do
    Enum.reduce(Map.values(players), %Room{join_code: join_code} , fn (player, room) ->
      Room.join(room, player)
    end)
  end

  test "Players can join room", %{players: players, join_code: join_code} do
    room = build_room(players, join_code)
    assert length(Room.joined_players(room)) === 4
  end

  test "Players can make picks", %{players: players, join_code: join_code} do
    room = build_room(players, join_code)
    crushes = [b, c, s, r ] = [
      "Blaine",
      "Callie",
      "Sammy",
      "Reggie",
    ]

    %{
      player1: player1,
      player2: player2,
      player3: player3,
      player4: player4
    } = players

    room = Room.set_player_picks(room, player1.id, %{
      "self" => b,
      player2.id => b,
      player3.id => b,
      player4.id => r,
    })
    room = Room.set_player_picks(room, player2.id, %{
      "self" => s,
      player1.id => b,
      player3.id => b,
      player4.id => r,
    })
    room = Room.set_player_picks(room, player3.id, %{
      "self" => b,
      player2.id => b,
      player1.id => b,
      player4.id => r,
    })
    room = Room.set_player_picks(room, player4.id, %{
      "self" => s,
      player2.id => c,
      player1.id => c,
      player3.id => c,
    })

    assert Room.get_player(room, player1.id) |> Player.has_picks?()
    assert Room.get_player(room, player2.id) |> Player.has_picks?()
    assert Room.get_player(room, player3.id) |> Player.has_picks?()
    assert Room.get_player(room, player4.id) |> Player.has_picks?()

    room = Room.end_round(room)


    IO.inspect Room.scoreboard(room)

  end

end
