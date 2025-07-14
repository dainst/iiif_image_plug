defmodule IIIFImagePlug.V3 do
  alias Plug.Conn

  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.Data

  import Plug.Conn

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
  The [extra formats](https://iiif.io/api/image/3.0/#57-extra-functionality) your service can deliver.

  ### `:temp_dir` (default: Evaluates [System.tmp_dir!()](https://hexdocs.pm/elixir/System.html#tmp_dir!/0) and creates
  a directory "iiif_image_plug" there.

  Because of how the TIF file format is structured, the plug can not stream the image if tif was requested as the response
  [format](https://iiif.io/api/image/3.0/#45-format). Instead, the image gets first written to a temporary file, which is then streamed
  from disk and finally getting deleted.

  If you want to forgo this file creation, you can set this option to `:buffer` instead of a file path. This will configure
  the plug to write the complete image to memory instead of disk - which is faster but also may cause memory issues if
  very large images are requested.

  ### `:scheme` (optional)
  Callback function to override the scheme evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.

  ### `:host` (optional)
  Callback function to override the host evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.

  ### `:port` (optional)
  Callback function to override the port evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.

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
  """

  defmodule Settings do
    @moduledoc false

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
      :status_callbacks,
      :temp_dir
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
      :status_callbacks,
      :temp_dir
    ]
  end

  @callback identifier_to_path(identifier :: String.t()) ::
              {:ok, String.t()} | {:error, atom()}
  @callback send_error(
              conn :: Conn.t(),
              status_code :: number(),
              error_code :: atom(),
              error_msg :: String.t()
            ) ::
              Conn.t() | no_return()

  defmacro __using__(_opts) do
    #### do something with opts
    quote do
      #### return some code to inject in the caller
      import Plug.Conn

      @behaviour Plug
      @behaviour IIIFImagePlug.V3

      @impl Plug
      def init(opts), do: IIIFImagePlug.V3.init(opts)

      @impl Plug
      def call(conn, opts), do: IIIFImagePlug.V3.call(conn, opts, __MODULE__)

      def scheme(), do: IIIFImagePlug.V3.scheme()
      def host(), do: IIIFImagePlug.V3.host()
      def port(), do: IIIFImagePlug.V3.port()

      def rights(identifier), do: IIIFImagePlug.V3.rights(identifier)
      def part_of(identifier), do: IIIFImagePlug.V3.part_of(identifier)
      def see_also(identifier), do: IIIFImagePlug.V3.see_also(identifier)
      def service(identifier), do: IIIFImagePlug.V3.service(identifier)

      # See https://dockyard.com/blog/2024/04/18/use-macro-with-defoverridable-function-fallbacks
      #
      # Basically if no `send_error/3` is defined by the user of the library, this will use the `send_error/3`
      # defined in the V3 module below. If the user creates a custom implementation, this would normally 100%
      # replace the default. Because we want to give the users the opportunity to customize only specific
      # errors, the @before_compile below will re-add our defaults as a fallback.

      def send_error(%Conn{} = conn, status_code, error_type, error_msg) do
        IIIFImagePlug.V3.send_error(conn, status_code, error_type, error_msg)
      end

      @before_compile {IIIFImagePlug.V3, :add_send_error_fallback}

      defoverridable scheme: 0,
                     host: 0,
                     port: 0,
                     rights: 1,
                     part_of: 1,
                     see_also: 1,
                     service: 1,
                     send_error: 4
    end
  end

  defmacro add_send_error_fallback(_env) do
    quote do
      def send_error(%Conn{} = conn, status_code, error_type, error_msg) do
        IIIFImagePlug.V3.send_error(conn, status_code, error_type, error_msg)
      end
    end
  end

  @default_preferred_format [:jpg]
  @default_extra_formats [:webp, :png, :tif]

  @default_max_width Application.compile_env(:iiif_image_plug, :max_width, 10000)
  @default_max_height Application.compile_env(:iiif_image_plug, :max_height, 10000)
  @default_max_area Application.compile_env(:iiif_image_plug, :max_area, 10000 * 10000)

  def init(opts) when is_map(opts) do
    temp_dir = opts[:temp_dir] || Path.join(System.tmp_dir!(), "iiif_image_plug")

    if temp_dir != :buffer do
      File.mkdir_p!(temp_dir)
    end

    %Settings{
      max_width: opts[:max_width] || @default_max_width,
      max_height: opts[:max_height] || @default_max_height,
      max_area: opts[:max_area] || @default_max_area,
      temp_dir: temp_dir,
      preferred_formats: opts[:preferred_formats] || @default_preferred_format,
      extra_formats: opts[:extra_formats] || @default_extra_formats
    }
  end

  def call(%Plug.Conn{path_info: [identifier]} = conn, _settings, module) do
    conn
    |> resp(:found, "")
    |> put_resp_header(
      "location",
      "#{construct_image_id(conn, identifier, module)}/info.json"
    )
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        settings,
        module
      ) do
    case generate_image_info(conn, identifier, settings, module) do
      {:ok, info} ->
        conn
        |> put_resp_content_type("application/ld+json")
        |> send_resp(200, Jason.encode!(info))

      {:error, :no_file} ->
        module.send_error(
          conn,
          404,
          :no_file,
          nil
        )

      {:error, :no_image_file} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        module.send_error(
          conn,
          500,
          :internal_error,
          nil
        )
    end
  end

  def call(
        %Plug.Conn{
          path_info: [identifier, region, size, rotation, quality_and_format]
        } = conn,
        %Settings{
          temp_dir: temp_dir
        } =
          settings,
        module
      ) do
    case Data.get(
           identifier,
           URI.decode(region),
           URI.decode(size),
           URI.decode(rotation),
           quality_and_format,
           settings,
           module
         ) do
      {%Image{} = image, format} ->
        cond do
          format == "tif" and temp_dir == :buffer ->
            send_buffered(conn, image, format)

          format == "tif" ->
            prefix = :crypto.strong_rand_bytes(8) |> Base.url_encode64() |> binary_part(0, 8)

            file_name =
              "#{prefix}_#{quality_and_format}"

            send_temporary_file(conn, image, Path.join(temp_dir, file_name))

          true ->
            send_stream(conn, image, format)
        end

      {:error, :no_file} ->
        module.send_error(
          conn,
          404,
          :no_file,
          nil
        )

      {:error, :no_image_file} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        module.send_error(
          conn,
          500,
          :internal_error,
          nil
        )

      {:error, type} ->
        module.send_error(
          conn,
          400,
          type,
          nil
        )
    end
  end

  def call(
        conn,
        _settings,
        module
      ) do
    module.send_error(
      conn,
      404,
      :unknown_route,
      nil
    )
  end

  defp send_buffered(conn, %Image{} = image, format) do
    {:ok, buffer} = Image.write_to_buffer(image, ".#{format}")
    send_resp(conn, 200, buffer)
  end

  defp send_temporary_file(conn, %Image{} = image, file_path) do
    parent = self()

    spawn(fn ->
      Process.monitor(parent)

      receive do
        {:DOWN, _ref, :process, _pid, _reason} ->
          File.rm(file_path)
      end
    end)

    Image.write_to_file(image, file_path)
    send_file(conn, 200, file_path)
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

  def send_error(conn, status_code, error_type, error_msg) do
    body =
      %{error: error_type}

    body =
      if error_msg do
        Map.put(body, :error_msg, error_msg)
      else
        body
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      status_code,
      Jason.encode!(body)
    )
  end

  def construct_image_id(
        %Conn{} = conn,
        identifier,
        module
      )
      when is_binary(identifier) do
    scheme = module.scheme() || conn.scheme
    host = module.host() || conn.scheme
    port = module.port() || conn.port

    Enum.join([
      scheme,
      "://",
      host,
      if(port != nil, do: ":#{port}", else: ""),
      if(conn.script_name != [], do: Path.join(["/"] ++ conn.script_name), else: ""),
      "/",
      identifier
    ])
  end

  def scheme(), do: nil
  def host(), do: nil
  def port(), do: nil

  def generate_image_info(conn, identifier, settings, module) do
    with {:identifier, {:ok, path}} <- {:identifier, module.identifier_to_path(identifier)},
         {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <- {:file_opened, Image.new_from_file(path)} do
      {
        :ok,
        %{
          "@context": "http://iiif.io/api/image/3/context.json",
          id: "#{construct_image_id(conn, identifier, module)}",
          type: "ImageService3",
          protocol: "http://iiif.io/api/image",
          width: Image.width(file),
          height: Image.height(file),
          profile: "level2",
          maxHeight: settings.max_height,
          maxWidth: settings.max_width,
          maxArea: settings.max_area,
          extra_features: [
            "mirroring",
            "regionByPct",
            "regionByPx",
            "regionSquare",
            "rotationArbitrary",
            "sizeByConfinedWh",
            "sizeByH",
            "sizeByPct",
            "sizeByW",
            "sizeByWh",
            "sizeUpscaling"
          ],
          preferredFormat: settings.preferred_formats,
          extraFormats: settings.extra_formats,
          extraQualities: [:color, :gray, :bitonal]
        }
        |> maybe_add_rights(identifier, module)
        |> maybe_add_part_of(identifier, module)
        |> maybe_add_see_also(identifier, module)
        |> maybe_add_service(identifier, module)
        |> maybe_add_sizes(file, path)
      }
    else
      {:identifier, _} ->
        {:error, :unknown_identifier}

      {:file_exists, false} ->
        {:error, :no_file}

      {:file_opened, _} ->
        {:error, :no_image_file}
    end
  end

  def rights(_identifier), do: {:ok, nil}
  def part_of(_identifier), do: {:ok, []}
  def see_also(_identifier), do: {:ok, []}
  def service(_identifier), do: {:ok, []}

  defp maybe_add_rights(%{} = info, identifier, module) do
    case module.rights(identifier) do
      {:ok, nil} -> info
      {:ok, val} -> Map.put(info, :rights, val)
      _ -> info
    end
  end

  defp maybe_add_part_of(%{} = info, identifier, module) do
    case module.part_of(identifier) do
      {:ok, []} -> info
      {:ok, val} -> Map.put(info, :part_of, val)
      _ -> info
    end
  end

  defp maybe_add_see_also(%{} = info, identifier, module) do
    case module.see_also(identifier) do
      {:ok, []} -> info
      {:ok, val} -> Map.put(info, :see_also, val)
      _ -> info
    end
  end

  defp maybe_add_service(%{} = info, identifier, module) do
    case module.service(identifier) do
      {:ok, []} -> info
      {:ok, val} -> Map.put(info, :service, val)
      _ -> info
    end
  end

  defp maybe_add_sizes(info, base_image, path) do
    page_count =
      try do
        Image.n_pages(base_image)
      rescue
        _ -> 1
      end

    if page_count > 1 do
      last_page = page_count - 1

      sizes =
        0..last_page
        |> Stream.map(fn page ->
          {:ok, page_image} = Image.new_from_file(path, page: page)

          width = Image.width(page_image)
          height = Image.height(page_image)

          %{
            type: "Size",
            width: width,
            height: height
          }
        end)
        |> Stream.reject(fn %{width: width} ->
          width == Image.width(base_image)
        end)
        |> Enum.sort_by(fn %{width: width} -> width end)

      Map.put(info, :sizes, sizes)
    else
      info
    end
  end
end
