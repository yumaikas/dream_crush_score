defmodule DreamCrushScoreWeb.PageController do
  use DreamCrushScoreWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
