defmodule DevServerHelper do
  @moduledoc false

  def get_host() do
    "localhost"
  end

  def get_port() do
    4000
  end

  def identifier_to_path(identifier) do
    "test/images/#{identifier}"
  end

  def handle_404(conn, _plug_info) do
    response_body =
      cond do
        Plug.Conn.request_url(conn)
        |> String.ends_with?(".json") ->
          Jason.encode!(%{"reason" => "not found from custom 404 handler"})

        true ->
          # As default we assume an image was requested and we return the fallback png.
          File.read!(Application.app_dir(:iiif_image_plug, "priv/image_not_found.webp"))
      end

    Plug.Conn.send_resp(
      conn,
      404,
      response_body
    )
  end

  def get_rights(_identifier) do
    {:ok, "https://creativecommons.org/publicdomain/zero/1.0/"}
  end
end
