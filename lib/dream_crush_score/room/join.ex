defmodule DreamCrushScore.Room.Join do
  use Ecto.Schema
  import Ecto.Changeset
  alias DreamCrushScore.Room.Join

  embedded_schema do
    field :code, :string
    field :name, :string
  end

  @doc false
  def changeset(%__MODULE__{} = join, attrs) do
    join
    |> cast(attrs, [:code, :name])
    |> validate_required([:code, :name])
  end
end
