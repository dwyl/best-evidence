defmodule Bep.PicoSearchController do
  use Bep.Web, :controller
  alias Bep.{NoteSearch, PicoSearch, PicoOutcome, Search}
  alias Ecto.Changeset

  def new(conn, %{"note_id" => note_id, "search_id" => search_id}) do
    search = Repo.get(Search, search_id)
    note_search = Repo.get_by(NoteSearch, search_id: search_id)
    changeset = PicoSearch.changeset(%PicoSearch{})

    assigns = [
      changeset: changeset,
      note_id: note_id,
      search: search,
      outcomes: [],
      note_search: note_search
    ]

    render(conn, "new.html", assigns)
  end

  def create(conn, %{"pico_search" => pico_search_params} = params) do
    pico_search_params = update_prob(pico_search_params)
    search_id = pico_search_params["search_id"]
    search = Repo.get(Search, search_id)

    pico_outcomes = get_pico_outcomes(pico_search_params)
    pico_search = insert_or_update_pico(pico_search_params)

    Enum.each(pico_outcomes, fn(outcome) ->
      %PicoOutcome{}
      |> PicoOutcome.changeset(outcome)
      |> Changeset.put_assoc(:pico_search, pico_search)
      |> Repo.insert!()
    end)

    case Map.get(params, "search_trip") do
      nil -> # Save and continue later route
        redirect(conn, to: search_path(conn, :index))
      "true" -> # search api with pico search (regular search for now)
        user = conn.assigns.current_user
        search_data =
          %{"term" => search.term}
          |> Search.search_data_for_create(user)

        search =
          search
          |> Changeset.change(number_results: search_data.data["total"])
          |> Repo.update!(force: true)

        pico_search = PicoSearch.get_pico_search(search)

        assigns = [
          pico_search: pico_search,
          search: search,
          data: search_data.data,
          bg_colour: get_client_colour(conn, :login_page_bg_colour),
          search_bar_colour: get_client_colour(conn, :search_bar_colour)
        ]
        render(conn, Bep.SearchView, "results.html", assigns)
    end
  end

  def edit(conn, %{"id" => pico_search_id, "note_id" => note_id, "search_id" => search_id}) do
    pico_search = Repo.get(PicoSearch, pico_search_id)
    note_search = Repo.get_by(NoteSearch, search_id: search_id)

    outcomes_query =
      from po in PicoOutcome,
      where: po.pico_search_id == ^pico_search_id,
      order_by: [desc: po.id],
      limit: 9

    pico_outcomes =
      outcomes_query
      |> Repo.all()
      |> Enum.sort(&(&1.o_index < &2.o_index))
      |> Enum.uniq_by(&(&1.o_index))

    search = Repo.get(Search, search_id)
    changeset = PicoSearch.changeset(pico_search)

    assigns = [
      changeset: changeset,
      note_id: note_id,
      search: search,
      outcomes: pico_outcomes,
      note_search: note_search
    ]

    render(conn, "new.html", assigns)
  end

  # Helpers
  defp update_prob(params) do
    prob = params["probability"]
    prob = Regex.replace(~r/\D/, prob, "")
    Map.put(params, "probability", prob)
  end

  defp get_pico_outcomes(pico_search) do
    pico_search
    |> Map.keys()
    |> Enum.filter(&(&1 =~ "outcome_input"))
    |> Enum.reduce([], fn(key, acc) ->
      value = Map.get(pico_search, key)
      case value == "" do
        true -> acc
        false ->
          [_ , index] = String.split(key, "outcome_input")
          pico_outcome = %{
            o: Map.get(pico_search, "outcome_input#{index}"),
            o_index: Map.get(pico_search, "outcome_index#{index}"),
            benefit: Map.get(pico_search, "outcome_benefit#{index}")
          }
          [pico_outcome | acc]
      end
    end)
  end

  defp insert_or_update_pico(pico_search_params) do
    note_id = pico_search_params["note_id"]
    pico_search = Repo.get_by(PicoSearch, note_search_id: note_id)
    note_search = Repo.get(NoteSearch, note_id)

    case pico_search do
      nil ->
        %PicoSearch{}
        |> PicoSearch.changeset(pico_search_params)
        |> Changeset.put_assoc(:note_search, note_search)
        |> Repo.insert!()
      pico_search ->
        pico_search
        |> PicoSearch.changeset(pico_search_params)
        |> Repo.update!()
    end
  end
end
