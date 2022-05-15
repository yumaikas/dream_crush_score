
defmodule DreamCrushScoreWeb.GamePlayerLive do
  use DreamCrushScoreWeb, :live_view


  def mount(_params, _session, socket) do

    {:ok, socket}
  end

  def handle_info({:live_session_updated, session}, socket) do
    socket = assign(socket, :join_code, session["join_code"])
    {:noreply, socket}
  end

end
