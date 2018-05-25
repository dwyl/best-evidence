defmodule Bep.UserController do
  use Bep.Web, :controller
  alias Bep.{Auth, Client, Type, User}
  alias Ecto.Changeset

  def new(conn, _params) do
    types =
      Type
      |> Repo.all()
      |> Type.filter_super_admin()

    changeset = User.changeset(%User{})
    bg_colour = get_client_colour(conn, :login_page_bg_colour)
    btn_colour = get_client_colour(conn, :btn_colour)

    render(
      conn,
      "new.html",
      changeset: changeset,
      types: types,
      bg_colour: bg_colour,
      btn_colour: btn_colour
    )
  end

  def create(conn, %{"user" => user_params}) do
    bg_colour = get_client_colour(conn, :login_page_bg_colour)
    btn_colour = get_client_colour(conn, :btn_colour)

    types =
      Type
      |> Repo.all()
      |> Type.filter_super_admin()

    user_types =
      types
      |> Enum.filter(fn(t) ->
        user_params["#{t.id}"] == "true"
      end)

    client = conn.assigns.client

    user_changeset =
      %User{}
      |> User.registration_changeset(user_params)
      |> Changeset.put_assoc(:types, user_types)
      |> Changeset.put_assoc(:client, client)

    case Repo.insert(user_changeset) do
      {:ok, user} ->
        conn
        |> Auth.login(user)
        |> put_flash(:info, "Welcome to BestEvidence!")
        |> redirect(to: page_path(conn, :index))
      {:error, %{errors: [email: {"has already been taken", []}]}} ->
        slug = conn.assigns.client.slug
        path =
          case slug do
            "default" ->
              session_path(conn, :new)
            _ ->
              client_slug_session_path(conn, :new, slug)

          end

        redirect(conn, to: path)
      {:error, changeset} ->
        render(
          conn,
          "new.html",
          changeset: changeset,
          types: types,
          bg_colour: bg_colour,
          btn_colour: btn_colour
        )
    end
  end

  def update(conn, %{"types" => types_params}) do
    types =
      Type
      |> Repo.all()
      |> Type.filter_super_admin

    user_types =
      types
      |> Enum.filter(fn(t) ->
        types_params["#{t.id}"] == "true"
      end)

    user =
      User
      |> Repo.get(conn.assigns.current_user.id)
      |> Repo.preload(:types)

    changeset =
      user
      |> Changeset.change()
      |> Changeset.put_assoc(:types, user_types)

    Repo.update!(changeset)
    redirect(conn, to: page_path(conn, :index))
  end

  def delete(conn, _) do
   conn
   |> Auth.logout()
   |> redirect(to: page_path(conn, :index))
 end

end
