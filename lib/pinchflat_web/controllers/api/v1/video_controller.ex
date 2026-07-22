defmodule PinchflatWeb.Api.V1.VideoController do
  use PinchflatWeb, :controller

  alias Pinchflat.Media

  def index(conn, _params) do
    videos = Media.list_media_items()

    result =
      videos
      |> Enum.filter(fn video -> not is_nil(video.media_filepath) end)
      |> Enum.map(fn video ->
        %{
          id: video.id,
          title: video.title,
          description: video.description,
          thumbnail_url: thumbnail_url(conn, video),
          stream_url: stream_url(conn, video)
        }
      end)

    json(conn, result)
  end

  def delete(conn, %{"id" => id}) do
    id
    |> Media.get_media_item!()
    |> Media.delete_media_item(delete_files: true)

    send_resp(conn, 204, "")
  end

  defp thumbnail_url(conn, video) do
    if video.media_filepath do
      extension =
        if video.thumbnail_filepath do
          Path.extname(video.thumbnail_filepath)
        else
          ".jpg"
        end

      port_suffix = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
      "#{conn.scheme}://#{conn.host}#{port_suffix}/media/#{video.uuid}/episode_image#{extension}"
    else
      nil
    end
  end

  defp stream_url(conn, video) do
    port_suffix = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port_suffix}/media/#{video.uuid}/stream"
  end
end
