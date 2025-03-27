defmodule IIIFImagePlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias IIIFImagePlug.V3.Size.Scaling

  alias IIIFImagePlug.V3.{
    Data,
    Information,
    Quality
  }

  alias Vix.Vips.Image

  require Logger

  @moduledoc """
  This plug implements the IIIF Image API version 3 (see also https://iiif.io/api/image/3.0/).

  # Options

  ## `:scheme` (default: `:http`)
  The scheme used to create the `id` image [information](https://iiif.io/api/image/3.0/#51-image-information-request) requests.

  ## `:host` (default: `"localhost"`)
  The host used to create the `id` image [information](https://iiif.io/api/image/3.0/#51-image-information-request) requests.

  ## `:port` (default: `nil`)
  The port used to create the `id` image [information](https://iiif.io/api/image/3.0/#51-image-information-request) requests.

  ## `:prefix` (default: `""`)
  The path prefix used to create the `id` image [information](https://iiif.io/api/image/3.0/#51-image-information-request) requests.

  ## `:max_width` (default: `10000`)
  The maximum image width the plug will serve.

  ## `:max_height` (default: `10000`)
  The maximum image height the plug will serve.

  ## `:max_area` (default: `100000000`)
  The maximum amount of image pixels the plug will serve (does not necessarily have to be `max_width` * `max_height`).

  ## `:preferred_formats` (default: `[:jpg]`)
  The [preferred formats](https://iiif.io/api/image/3.0/#55-preferred-formats) to be used for your service.

  ## `:extra_formats` (default: `[:png, :webp, :tif]`)
  The [extra formats](https://iiif.io/api/image/3.0/#57-extra-functionality) your service can deliver. Note that TIF files
  have to be buffered before they are sent, so large images might cause issues.

  ## `:identifier_to_path_callback` required
  An arity 1 callback function that resolves a given IIIF identifier to a file path (string).

  ## `:identifier_to_rights_callback` (optional)
  An arity 1 callback function that returns a [rights](https://iiif.io/api/image/3.0/#56-rights) statement for a given identifier.

  ## `:identifier_to_part_of_callback` (optional)
  An arity 1 callback function that returns a list of [part of](https://iiif.io/api/image/3.0/#58-linking-properties) properties for a given identifier.

  ## `:identifier_to_see_also_callback` (optional)
  An arity 1 callback function that returns a list of [see also](https://iiif.io/api/image/3.0/#58-linking-properties) properties for a given identifier.

  ## `:identifier_to_service_callback` (optional)
  An arity 1 callback function that returns a list of [service](https://iiif.io/api/image/3.0/#58-linking-properties) properties for a given identifier.

  ## `:status_callbacks` (optional)
  A map where each key is a HTTP status code (integer), and each value a callback that can be used to replace the plug's default response.
  """

  defmodule Settings do
    @enforce_keys [
      :scheme,
      :host,
      :port,
      :prefix,
      :max_width,
      :max_height,
      :max_area,
      :preferred_formats,
      :extra_formats,
      :identifier_to_path_callback,
      :identifier_to_rights_callback,
      :identifier_to_part_of_callback,
      :identifier_to_see_also_callback,
      :identifier_to_service_callback,
      :status_callbacks
    ]
    defstruct [
      :scheme,
      :host,
      :port,
      :prefix,
      :max_width,
      :max_height,
      :max_area,
      :preferred_formats,
      :extra_formats,
      :identifier_to_path_callback,
      :identifier_to_rights_callback,
      :identifier_to_part_of_callback,
      :identifier_to_see_also_callback,
      :identifier_to_service_callback,
      :status_callbacks
    ]
  end

  @default_preferred_format [:jpg]
  @default_extra_formats [:webp, :png, :tif]

  @default_max_width Application.compile_env(:iiif_image_plug, :max_width, 10000)
  @default_max_height Application.compile_env(:iiif_image_plug, :max_height, 10000)
  @default_max_area Application.compile_env(:iiif_image_plug, :max_area, 10000 * 10000)

  def init(opts) when is_map(opts) do
    %Settings{
      scheme: opts[:scheme] || :http,
      host: opts[:host] || "localhost",
      port: opts[:port],
      prefix:
        if opts[:prefix] do
          String.trim_trailing(opts[:prefix], "/")
        else
          ""
        end,
      max_width: opts[:max_width] || @default_max_width,
      max_height: opts[:max_height] || @default_max_height,
      max_area: opts[:max_area] || @default_max_area,
      preferred_formats: opts[:preferred_formats] || @default_preferred_format,
      extra_formats: opts[:extra_formats] || @default_extra_formats,
      identifier_to_path_callback:
        opts[:identifier_to_path_callback] ||
          raise("Missing callback used to construct file path from identifier."),
      identifier_to_rights_callback: opts[:identifier_to_rights_callback],
      identifier_to_part_of_callback: opts[:identifier_to_part_of_callback],
      identifier_to_see_also_callback: opts[:identifier_to_see_also_callback],
      identifier_to_service_callback: opts[:identifier_to_service_callback],
      status_callbacks: opts[:status_callbacks] || %{}
    }
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        %Settings{status_callbacks: status_callbacks} = settings
      ) do
    case Information.evaluate(identifier, settings) do
      {:ok, info} ->
        conn
        |> put_resp_content_type("application/ld+json")
        |> send_resp(200, Jason.encode!(info))

      {:file_exists, false} ->
        send_error(
          conn,
          404,
          %{
            description: "No file with identifier '#{identifier}'."
          },
          status_callbacks
        )

      {:file_opened, _} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        send_error(
          conn,
          500,
          %{},
          status_callbacks
        )
    end
  end

  def call(
        %Plug.Conn{
          path_info: [identifier, region, size, rotation, quality_and_format]
        } = conn,
        %Settings{
          identifier_to_path_callback: path_callback,
          status_callbacks: status_callbacks
        } =
          settings
      ) do
    path = path_callback.(identifier)

    with {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <- {:file_opened, Image.new_from_file(path)},
         {:quality_and_format_parsed, %{quality: quality, format: format}} <-
           {:quality_and_format_parsed, Quality.parse(quality_and_format, settings)} do
      page_count =
        try do
          Image.n_pages(file)
        rescue
          _ -> 1
        end

      if page_count > 1 do
        last_page = page_count - 1

        width = Image.width(file)

        pages =
          0..last_page
          |> Enum.map(fn page ->
            {:ok, page_image} = Image.new_from_file(path, page: page)

            page_width = Image.width(page_image)

            {page_image, %Scaling{scale: page_width / width}}
          end)

        Data.process_page_optimized(file, region, size, rotation, quality, settings, pages)
      else
        Data.process_basic(file, region, size, rotation, quality, settings)
      end
      |> case do
        %Image{} = transformed ->
          if format == "tif" do
            send_buffered(conn, transformed, format)
          else
            send_stream(conn, transformed, format)
          end

        {:error, msg} ->
          send_error(
            conn,
            400,
            %{error: msg},
            status_callbacks
          )
      end
    else
      {:file_exists, false} ->
        send_error(
          conn,
          404,
          %{
            description: "No file with identifier '#{identifier}'."
          },
          status_callbacks
        )

      {:file_opened, _} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        send_error(
          conn,
          500,
          %{},
          status_callbacks
        )

      {:quality_and_format_parsed, _} ->
        send_error(
          conn,
          400,
          %{
            description:
              "Could not find parse valid quality and format from '#{quality_and_format}'."
          },
          status_callbacks
        )
    end
  end

  def call(
        conn,
        %Settings{status_callbacks: callbacks}
      ) do
    send_error(
      conn,
      400,
      %{description: "Invalid request scheme.", path_info: conn.path_info},
      callbacks
    )
  end

  defp send_buffered(conn, %Image{} = image, format) do
    {:ok, buffer} = Image.write_to_buffer(image, ".#{format}")
    send_resp(conn, 200, buffer)
  end

  defp send_stream(conn, %Image{} = image, format) do
    stream = Image.write_to_stream(image, ".#{format}")

    conn = send_chunked(conn, 200)

    Enum.reduce_while(stream, conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  defp send_error(conn, code, info, status_callbacks)
       when is_map(info) and is_map(status_callbacks) do
    if status_callbacks[code] do
      status_callbacks[code].(conn, info)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        code,
        Jason.encode!(info)
      )
    end
  end
end
