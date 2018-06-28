defmodule Bep.MessagesController do
  use Bep.Web, :controller
  alias Bep.{Messages, Type}

  def view_messages(conn, %{"user" => user_id}) do
    assigns = [
      messages: Messages.get_messages(user_id),
      user: user_id,
      changeset: Messages.changeset(%Messages{})
    ]
    |> hide_nav_for_SA(conn)
    render(conn, :view, assigns)
  end

  def list_users(conn, _params) do
    assigns = [
      hide_navbar: true,
      users: Messages.get_user_list()
    ]
    render(conn, :list_users, assigns)
  end

  def create(conn, %{"message" => message}) do
    message = Map.put(message, "from_id", conn.assigns.current_user.id)
    to_user_id = message["to_user"]
    changeset = Messages.changeset(%Messages{}, message)

    case Repo.insert(changeset) do
      {:ok, _message} ->
        msg_sent_path = sa_messages_path(conn, :message_sent)
        redirect(conn, to: msg_sent_path)
      {:error, changeset} ->
        assigns = [
          messages: Messages.get_messages(to_user_id),
          user: to_user_id,
          hide_navbar: true,
          changeset: changeset
        ]
        render(conn, :view, assigns)
    end
  end

  def message_sent(conn, _params) do
    assigns = [hide_navbar: true]
    render(conn, :message_sent, assigns)
  end

  #Helpers
  defp hide_nav_for_SA(list, conn) do
    current_user_is_admin_bool =
      conn.assigns.current_user
      |> Repo.preload(:types)
      |> Map.get(:types)
      |> Type.is_type_admin?()

    case current_user_is_admin_bool do
      true ->
        [{:hide_navbar, current_user_is_admin_bool} | list]
      _ ->
        list
    end
  end
end