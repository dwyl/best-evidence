defmodule Bep.Publication do
  @moduledoc """
  Publication model
  """
  use Bep.Web, :model
  alias Bep.{BearAnswers, Repo, Search, SearchPublication}

  schema "publications" do
    field :url, :string
    field :value, :string
    field :tripdatabase_id, :string
    many_to_many :searches, Search,
      join_through: SearchPublication,
      unique: true
    has_many :bear_answers, BearAnswers
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:url, :value, :tripdatabase_id])
    |> validate_required([:url, :value, :tripdatabase_id])
    |> put_assoc(:searches, [Repo.get!(Search, params["search_id"])])
    |> unique_constraint(
        :searches,
        name: :searches_publications_search_id_publication_id_index,
        message: "Search already exists for this publication"
      )
  end

end
