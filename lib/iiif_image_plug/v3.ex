defmodule IIIFImagePlug.V3 do
  alias Plug.Conn

  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.{
    Options,
    Data
  }

  import Plug.Conn

  require Logger

  @moduledoc """
  This plug implements the IIIF Image API version 3 (see also https://iiif.io/api/image/3.0).
  """

  @doc """
  __Required__ callback function that resolves a given IIIF identifier to a file path (string).
  """
  @callback identifier_to_path(identifier :: String.t()) ::
              {:ok, String.t()} | {:error, atom()}

  @doc """
  __Optional__ callback function to override the scheme evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.
  """
  @callback scheme() :: String.t() | nil

  @doc """
  __Optional__ callback function to override the host evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.
  """
  @callback host() :: String.t() | nil

  @doc """
  __Optional__ callback function to override the port evaluated from the `%Plug.Conn{}`, useful if your Elixir app runs behind a proxy.
  """
  @callback port() :: pos_integer() | nil

  @doc """
  __Optional__ callback function that returns a [rights](https://iiif.io/api/image/3.0/#56-rights) statement for a given identifier. If
  `nil` is returned, the _rights_ key will be omitted in the _info.json_.
  """
  @callback rights(identifier :: String.t()) :: String.t() | nil

  @doc """
  __Optional__ callback function that returns a list of [part of](https://iiif.io/api/image/3.0/#58-linking-properties) properties for
  a given identifier. If an empty list is returned, the _partOf_ key will be omitted in the _info.json_.
  """
  @callback part_of(identifier :: String.t()) :: list()

  @doc """
  __Optional__ callback function that returns a list of [see also](https://iiif.io/api/image/3.0/#58-linking-properties) properties for
  a given identifier. If an empty list is returned, the _seeAlso_ key will be omitted in the _info.json_.
  """
  @callback see_also(identifier :: String.t()) :: list()

  @doc """
  __Optional__ callback function that returns a list of [service](https://iiif.io/api/image/3.0/#58-linking-properties) properties for
  a given identifier. If an empty list is returned, the _service_ key will be omitted in the _info.json_.
  """
  @callback service(identifier :: String.t()) :: list()

  @doc """
  __Optional__ callback function that lets you override the default plug error response, which is defined as follows:

      def send_error(conn, status_code, error_type) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          status_code,
          Jason.encode!(%{error: error_type})
        )
      end

  One use case might be sending your own placeholder image instead of the JSON for failed image requests.
  """
  @callback send_error(
              conn :: Conn.t(),
              status_code :: number(),
              error_code :: atom()
            ) :: Conn.t()

  defmacro __using__(_opts) do
    quote do
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
      # Basically if no `send_error/3` is defined by the user of the library, the plug will use the default
      # `send_error/3` defined in the V3 module below. If the user creates a custom implementation, this would
      # normally 100% replace the default. Because we want to give the users the opportunity to customize only specific
      # errors (based on pattern matching), the @before_compile below will re-add our defaults as a fallback.

      def send_error(%Conn{} = conn, status_code, error_type) do
        IIIFImagePlug.V3.send_error(conn, status_code, error_type)
      end

      @before_compile {IIIFImagePlug.V3, :add_send_error_fallback}

      defoverridable scheme: 0,
                     host: 0,
                     port: 0,
                     rights: 1,
                     part_of: 1,
                     see_also: 1,
                     service: 1,
                     send_error: 3
    end
  end

  defmacro add_send_error_fallback(_env) do
    quote do
      def send_error(%Conn{} = conn, status_code, error_type) do
        IIIFImagePlug.V3.send_error(conn, status_code, error_type)
      end
    end
  end

  def init(%Options{temp_dir: temp_dir} = opts) do
    if temp_dir != :buffer do
      File.mkdir_p!(temp_dir)
    end

    opts
  end

  def call(%Plug.Conn{path_info: [identifier]} = conn, _options, module) do
    conn
    |> resp(:found, "")
    |> put_resp_header(
      "location",
      "#{construct_image_id(conn, identifier, module)}/info.json"
    )
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        options,
        module
      ) do
    case generate_image_info(conn, identifier, options, module) do
      {:ok, info} ->
        conn
        |> put_resp_content_type("application/ld+json")
        |> send_resp(200, Jason.encode!(info))

      {:error, :no_file} ->
        module.send_error(
          conn,
          404,
          :no_file
        )

      {:error, :no_image_file} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        module.send_error(
          conn,
          500,
          :internal_error
        )
    end
  end

  @streamable ["jpg", "webp", "gif", "png"]

  def call(
        %Plug.Conn{
          path_info: [identifier, region, size, rotation, quality_and_format]
        } = conn,
        %Options{
          temp_dir: temp_dir
        } =
          options,
        module
      ) do
    case Data.get(
           identifier,
           URI.decode(region),
           URI.decode(size),
           URI.decode(rotation),
           quality_and_format,
           options,
           module
         ) do
      {%Image{} = image, format} ->
        cond do
          format not in @streamable and temp_dir == :buffer ->
            send_buffered(conn, image, format)

          format not in @streamable ->
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
          :no_file
        )

      {:error, :no_image_file} ->
        Logger.error("File matching identifier '#{identifier}' could not be opened as an image.")

        module.send_error(
          conn,
          500,
          :internal_error
        )

      {:error, type} ->
        module.send_error(
          conn,
          400,
          type
        )
    end
  end

  def call(
        conn,
        _options,
        module
      ) do
    module.send_error(
      conn,
      404,
      :unknown_route
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

  def send_error(conn, status_code, error_type) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      status_code,
      Jason.encode!(%{error: error_type})
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

  def generate_image_info(conn, identifier, options, module) do
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
          maxHeight: options.max_height,
          maxWidth: options.max_width,
          maxArea: options.max_area,
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
          preferredFormat: options.preferred_formats,
          extraFormats: options.extra_formats,
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

  def rights(_identifier), do: nil
  def part_of(_identifier), do: []
  def see_also(_identifier), do: []
  def service(_identifier), do: []

  defp maybe_add_rights(%{} = info, identifier, module) do
    case module.rights(identifier) do
      nil -> info
      value -> Map.put(info, :rights, value)
    end
  end

  defp maybe_add_part_of(%{} = info, identifier, module) do
    case module.part_of(identifier) do
      [] -> info
      values -> Map.put(info, :part_of, values)
    end
  end

  defp maybe_add_see_also(%{} = info, identifier, module) do
    case module.see_also(identifier) do
      [] -> info
      values -> Map.put(info, :see_also, values)
    end
  end

  defp maybe_add_service(%{} = info, identifier, module) do
    case module.service(identifier) do
      [] -> info
      values -> Map.put(info, :service, values)
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
