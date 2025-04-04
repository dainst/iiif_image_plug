defmodule IIIFImagePlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias Plug.Conn

  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.{
    Data,
    Information
  }

  require Logger

  @moduledoc """
  This plug implements the IIIF Image API version 3 (see also https://iiif.io/api/image/3.0/).

  ## Options

  ### `:identifier_to_path_callback` required
  An arity 1 callback function that resolves a given IIIF identifier to a file path (string).

  ### `:max_width` (default: `10000`)
  The maximum image width the plug will serve.

  ### `:max_height` (default: `10000`)
  The maximum image height the plug will serve.

  ### `:max_area` (default: `100000000`)
  The maximum amount of image pixels the plug will serve (does not necessarily have to be `max_width` * `max_height`).

  ### `:preferred_formats` (default: `[:jpg]`)
  The [preferred formats](https://iiif.io/api/image/3.0/#55-preferred-formats) to be used for your service.

  ### `:extra_formats` (default: `[:png, :webp, :tif]`)
  The [extra formats](https://iiif.io/api/image/3.0/#57-extra-functionality) your service can deliver. Note that TIF files
  have to be buffered before they are sent, so large images might cause issues.

  ### `:identifier_to_rights_callback` (optional)
  An arity 1 callback function that returns a [rights](https://iiif.io/api/image/3.0/#56-rights) statement for a given identifier.

  ### `:identifier_to_part_of_callback` (optional)
  An arity 1 callback function that returns a list of [part of](https://iiif.io/api/image/3.0/#58-linking-properties) properties for a given identifier.

  ### `:identifier_to_see_also_callback` (optional)
  An arity 1 callback function that returns a list of [see also](https://iiif.io/api/image/3.0/#58-linking-properties) properties for a given identifier.

  ### `:identifier_to_service_callback` (optional)
  An arity 1 callback function that returns a list of [service](https://iiif.io/api/image/3.0/#58-linking-properties) properties for a given identifier.

  ### `:status_callbacks` (optional)
  A map where each key is a HTTP status code (integer), and each value an arity 2 callback that can be used to replace the plug's default response. Each
  callback should accept a plug as its first parameter and a Map (containing the error message) as its second parameter.

  ### `:scheme` (optional)
  Override the scheme evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.

  ### `:host` (optional)
  Override the host evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.

  ### `:port` (optional)
  Override the port evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.
  """

  defmodule Settings do
    @enforce_keys [
      :identifier_to_path_callback,
      :scheme,
      :host,
      :port,
      :max_width,
      :max_height,
      :max_area,
      :preferred_formats,
      :extra_formats,
      :identifier_to_rights_callback,
      :identifier_to_part_of_callback,
      :identifier_to_see_also_callback,
      :identifier_to_service_callback,
      :status_callbacks
    ]
    defstruct [
      :identifier_to_path_callback,
      :scheme,
      :host,
      :port,
      :max_width,
      :max_height,
      :max_area,
      :preferred_formats,
      :extra_formats,
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
      identifier_to_path_callback:
        opts[:identifier_to_path_callback] ||
          raise("Missing callback used to construct file path from identifier."),
      scheme: opts[:scheme],
      host: opts[:host],
      port: opts[:port],
      max_width: opts[:max_width] || @default_max_width,
      max_height: opts[:max_height] || @default_max_height,
      max_area: opts[:max_area] || @default_max_area,
      preferred_formats: opts[:preferred_formats] || @default_preferred_format,
      extra_formats: opts[:extra_formats] || @default_extra_formats,
      identifier_to_rights_callback: opts[:identifier_to_rights_callback],
      identifier_to_part_of_callback: opts[:identifier_to_part_of_callback],
      identifier_to_see_also_callback: opts[:identifier_to_see_also_callback],
      identifier_to_service_callback: opts[:identifier_to_service_callback],
      status_callbacks: opts[:status_callbacks] || %{}
    }
  end

  def call(%Plug.Conn{path_info: [identifier]} = conn, settings) do
    conn
    |> resp(:found, "")
    |> put_resp_header(
      "location",
      "#{construct_id_url(conn, settings)}/#{identifier}/info.json"
    )
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        %Settings{status_callbacks: status_callbacks} = settings
      ) do
    case Information.get(identifier, conn, settings) do
      {:ok, info} ->
        conn
        |> put_resp_content_type("application/ld+json")
        |> send_resp(200, Jason.encode!(info))

      {:error, :no_file} ->
        send_error(
          conn,
          404,
          %{error: :no_file},
          status_callbacks
        )

      {:error, :no_image_file} ->
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
          status_callbacks: status_callbacks
        } =
          settings
      ) do
    case Data.get(
           identifier,
           URI.decode(region),
           URI.decode(size),
           URI.decode(rotation),
           quality_and_format,
           settings
         ) do
      {%Image{} = image, format} ->
        if format == "tif" do
          send_buffered(conn, image, format)
        else
          send_stream(conn, image, format)
        end

      {:error, :no_file} ->
        send_error(
          conn,
          404,
          %{error: :no_file},
          status_callbacks
        )

      {:error, :no_image_file} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        send_error(
          conn,
          500,
          %{},
          status_callbacks
        )

      {:error, msg} ->
        send_error(
          conn,
          400,
          %{error: msg},
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
      404,
      %{reason: "Unknown path.", path_info: conn.path_info},
      callbacks
    )
  end

  def construct_id_url(
        %Conn{} = conn,
        %Settings{
          scheme: scheme_override,
          host: host_override,
          port: port_override
        }
      ) do
    scheme = scheme_override || conn.scheme
    host = host_override || conn.host
    port = port_override || conn.port

    "#{scheme}://#{host}#{if port != nil do
      ":#{port}"
    else
      ""
    end}#{if conn.script_name != [], do: Path.join(["/"] ++ conn.script_name)}"
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
