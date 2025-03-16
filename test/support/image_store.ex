defmodule ImageStore do
  def identifier_to_path(identifier) do
    "image_store/#{identifier}"
  end

  def handle_404(conn, plug_info) do
    response_body =
      cond do
        Plug.Conn.request_url(conn)
        |> String.ends_with?(".json") ->
          Jason.encode!(plug_info)

        true ->
          # As default we assume an image was requested and we return the fallback png.
          File.read!(Application.app_dir(:iiif_image_plug, "priv/image_not_found.webp"))
      end

    Plug.Conn.resp(
      conn,
      404,
      response_body
    )
  end
end
