defmodule DreamCrushScore.Repo do
  use Ecto.Repo,
    otp_app: :dream_crush_score,
    adapter: Ecto.Adapters.SQLite3
end
