defmodule Bep.EvidenceChannel do
  use Bep.Web, :channel
  alias Bep.{Publication, User, Tripdatabase.HTTPClient}
  import Phoenix.View, only: [render_to_string: 3]

  def join("evidence:" <> search_id, _params, socket) do
    init_socket = socket
    |> assign(:page, 1)
    |> assign(:search_id, String.to_integer(search_id))
    {:ok, init_socket}
  end

  def handle_in(event, params, socket) do
    user = Repo.get(User, socket.assigns.user_id)
    handle_in(event, params, user, socket)
  end

  def handle_in("evidence", params, _user, socket) do
    save_publication(socket, params)
  end

  def handle_in("scroll", params, _user, socket) do
    page = socket.assigns.page
    html = load_page(socket, %{term: params["term"]})
    update_socket = assign(socket, :page, page  + 1)
    data = %{
      page: update_socket.assigns.page,
      content: html
    }
    {:reply, {:ok, data}, update_socket}
  end

  defp save_publication(socket, payload) do
    changeset = Publication.changeset(%Publication{}, payload)
    tripdatabase_id = changeset.changes.tripdatabase_id
    publication = Repo.insert(
      changeset,
      on_conflict: [set: [tripdatabase_id:	tripdatabase_id]],
      conflict_target:	:tripdatabase_id
    )

    case publication do
      {:ok, _publication} ->
        {:reply, :ok, socket}
      {:error, _changeset} ->
        {:reply, {:error, %{error: changeset}}, socket}
    end
  end

  defp load_page(socket, %{term: term}) do
    skip = socket.assigns.page * 20
    {:ok, data} = HTTPClient.search(term, %{skip: skip})
    render_to_string(
      Bep.SearchView,
      "evidences.html",
      data: data, start: skip + 1, id: socket.assigns.search_id)
  end

end
