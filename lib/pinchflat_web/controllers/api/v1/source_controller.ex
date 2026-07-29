defmodule PinchflatWeb.Api.V1.SourceController do
  use PinchflatWeb, :controller

  alias Pinchflat.Sources

  def index(conn, _params) do
    sources = Sources.list_sources()

    result =
      Enum.map(sources, fn source ->
        %{
          id: source.id,
          uuid: source.uuid,
          name: source.custom_name,
          description: source.description,
          collection_type: source.collection_type
        }
      end)

    json(conn, result)
  end

  def create(conn, %{"url" => url}) do
    case Sources.create_source(%{"original_url" => url}) do
      {:ok, _source} ->
        conn
        |> put_status(:created)
        |> json(%{status: "success"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", errors: translate_errors(changeset)})
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
