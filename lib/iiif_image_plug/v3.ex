defmodule IIIFImagePlug.V3 do
  alias Plug.Conn

  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.{
    Data,
    DataRequest,
    Info,
    InfoRequest,
    Options,
    RequestError
  }

  import Plug.Conn

  require Logger

  @moduledoc """
  This plug implements the IIIF Image API version 3 (see also https://iiif.io/api/image/3.0).
  """

  @doc """
  __Required__ callback function invoked on information requests (`info.json`), that maps the given _identifier_ to an
  image file.

  ## Returns

  - `{:ok, info_request}` on success, where `info_request` is a `IIIFImagePlug.V3.InfoRequest` struct.
  - `{:error, request_error}` otherwise, where `request_error` is a `IIIFImagePlug.V3.RequestError` struct.

  """
  @callback info_request(identifier :: String.t()) ::
              {:ok, InfoRequest.t()} | {:error, RequestError.t()}

  @doc """
  __Required__ callback function invoked on image data requests, that maps the given _identifier_ to an
  image file.

  ## Returns

  - `{:ok, info_request}` on success, where `info_request` is a `IIIFImagePlug.V3.InfoRequest` struct.
  - `{:error, request_error}` otherwise, where `request_error` is a `IIIFImagePlug.V3.RequestError` struct.
  """
  @callback data_request(identifier :: String.t()) ::
              {:ok, DataRequest.t()} | {:error, RequestError.t()}

  @doc """
  __Optional__ callback function to override the `:scheme` ("http" or "https") evaluated from the `Plug.Conn`, useful if your Elixir app runs behind a
  proxy.
  """
  @callback scheme() :: String.t() | nil

  @doc """
  __Optional__ callback function to override the `:host` evaluated from the `Plug.Conn`, useful if your Elixir app runs behind a proxy.
  """
  @callback host() :: String.t() | nil

  @doc """
  __Optional__ callback function to override the `:port` evaluated from the `Plug.Conn`, useful if your Elixir app runs behind a proxy.
  """
  @callback port() :: pos_integer() | nil

  @doc """
  __Optional__ callback function that lets you override the default plug error response.

  The default is defined as follows:

      def send_error(conn, status_code, error_type) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          status_code,
          Jason.encode!(%{error: error_type})
        )
      end

  One use case might be sending your own placeholder image instead of the JSON for failed data requests.
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
                     send_error: 3
    end
  end

  @doc false
  defmacro add_send_error_fallback(_env) do
    quote do
      def send_error(%Conn{} = conn, status_code, error_type) do
        IIIFImagePlug.V3.send_error(conn, status_code, error_type)
      end
    end
  end

  @doc false
  def init(%Options{temp_dir: temp_dir} = opts) do
    if temp_dir != :buffer do
      File.mkdir_p!(temp_dir)
    end

    opts
  end

  @doc false
  def call(%Plug.Conn{path_info: [identifier]} = conn, _options, module) do
    conn
    |> resp(:found, "")
    |> put_resp_header(
      "location",
      "#{Info.construct_image_id(conn, identifier, module)}/info.json"
    )
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        %Options{} = options,
        module
      ) do
    case Info.generate_image_info(conn, identifier, options, module) do
      {:ok, {conn, info}} ->
        conn
        |> put_resp_content_type("application/ld+json")
        |> send_resp(200, Jason.encode!(info))

      {:error, %RequestError{status_code: code, msg: msg, response_headers: headers}} ->
        headers
        |> Enum.reduce(conn, fn {key, value}, acc ->
          Plug.Conn.put_resp_header(acc, key, value)
        end)
        |> module.send_error(
          code,
          msg
        )

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
           conn,
           identifier,
           URI.decode(region),
           URI.decode(size),
           URI.decode(rotation),
           quality_and_format,
           options,
           module
         ) do
      {
        %Plug.Conn{} = conn,
        %Image{} = image,
        format
      } ->
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

      {:error, %RequestError{status_code: code, msg: msg, response_headers: headers}} ->
        headers
        |> Enum.reduce(conn, fn {key, value}, acc ->
          Plug.Conn.put_resp_header(acc, key, value)
        end)
        |> module.send_error(
          code,
          msg
        )

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

  @doc false
  def send_error(conn, status_code, error_type) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      status_code,
      Jason.encode!(%{error: error_type})
    )
  end

  @doc false
  def scheme(), do: nil

  @doc false
  def host(), do: nil

  @doc false
  def port(), do: nil
end
