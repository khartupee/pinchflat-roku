defmodule PinchflatWeb.Api.V1.VideoController do
  use PinchflatWeb, :controller

  alias Pinchflat.Media
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Repo

  require Logger

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
          duration_seconds: video.duration_seconds,
          playback_position_seconds: video.playback_position_seconds,
          source_id: video.source_id,
          source_name: video.source.custom_name,
          uploaded_at: video.uploaded_at,
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

  def ignore(conn, %{"id" => id}) do
    id
    |> Media.get_media_item!()
    |> Media.delete_media_files(%{prevent_download: true})

    send_resp(conn, 204, "")
  end

  def save_progress(conn, %{"id" => id, "position" => position}) do
    media_item = Media.get_media_item!(id)

    case Media.update_media_item(media_item, %{playback_position_seconds: position}) do
      {:ok, _} -> send_resp(conn, 204, "")
      {:error, _} -> json(conn, %{error: "Invalid position"})
    end
  end

  # Streams a video file by numeric ID (auth required via :api_v1 pipeline).
  # Supports HTTP range requests for seeking/pausing.
  # This is an additive endpoint for Roku clients that cannot embed credentials in URLs.
  def stream(conn, %{"id" => id}) do
    media_item = Media.get_media_item!(id)

    if File.exists?(media_item.media_filepath) do
      file_size = File.stat!(media_item.media_filepath).size
      mime_type = MIME.from_path(media_item.media_filepath)

      case parse_range(conn, file_size) do
        {:ok, {start_pos, end_pos}} ->
          Logger.debug("Streaming media item #{id} from #{start_pos} to #{end_pos}")
          length = end_pos - start_pos + 1

          conn
          |> put_resp_content_type(mime_type)
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_header("content-range", "bytes #{start_pos}-#{end_pos}/#{file_size}")
          |> put_resp_header("content-length", to_string(length))
          |> put_resp_header("content-disposition", "inline; filename=\"#{media_item.title}\"")
          |> send_file(206, media_item.media_filepath, start_pos, length)

        {:error, :invalid_range} ->
          conn
          |> put_resp_content_type(mime_type)
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_header("content-range", "bytes 0-#{file_size - 1}/#{file_size}")
          |> put_resp_header("content-length", to_string(file_size))
          |> put_resp_header("content-disposition", "inline; filename=\"#{media_item.title}\"")
          |> send_file(200, media_item.media_filepath)
      end
    else
      send_resp(conn, 404, "File not found")
    end
  end

  defp parse_range(conn, file_size) do
    with [range_header | _] <- get_req_header(conn, "range"),
         ["bytes", range] <- String.split(range_header, "="),
         [start_pos, end_pos] <- String.split(range, "-", parts: 2) do
      validate_range(start_pos, end_pos, file_size)
    else
      _ -> {:error, :invalid_range}
    end
  end

  defp validate_range(start_pos, end_pos, file_size) do
    case {Integer.parse(start_pos), Integer.parse(end_pos)} do
      {{s, _}, {e, _}} when is_integer(s) and is_integer(e) and s >= 0 and e < file_size and s <= e ->
        {:ok, {s, e}}

      {{s, _}, :error} when is_integer(s) and s >= 0 and s < file_size ->
        # Open-ended range like "bytes=0-" — serve to end of file
        {:ok, {s, file_size - 1}}

      _ ->
        {:error, :invalid_range}
    end
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
    "#{conn.scheme}://#{conn.host}#{port_suffix}/api/v1/videos/#{video.id}/stream"
  end
end
