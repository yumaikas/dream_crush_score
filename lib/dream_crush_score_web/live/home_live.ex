defmodule DreamCrushScoreWeb.HomeLive do
  use DreamCrushScoreWeb, :live_view
  alias DreamCrushScore.Room.Join

  def mount(_params, _session, socket) do
    socket = socket
    |> assign(join_form: Join.changeset(%Join{}, %{code: ""}))
    {:ok, socket}
  end

  @impl true
  def handle_event("try_join_room", %{"join" => %{"code" => code}}, socket) do
    {:noreply, socket}
  end

end
