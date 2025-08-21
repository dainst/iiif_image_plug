defmodule IIIFImagePlug.V3 do
  alias Plug.Conn

  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.{
    Data,
    DataRequestMetadata,
    Info,
    InfoRequestMetadata,
    Options,
    RequestError
  }

  import Plug.Conn

  require Logger

  @moduledoc """
  This plug implements the IIIF Image API version 3 (see also https://iiif.io/api/image/3.0).
  """

  @doc """
  __Optional__ callback function that gets triggered at the start of an image information request,
  before any further evaluation is done.

  If you want the plug to continue processing the information request, return `{:continue, conn}`,
  otherwise you might instruct the plug to stop further processing by returning `{:stop, conn}`.
  This can be used in conjunction with `c:IIIFImagePlug.V3.info_response/1` to implement your
  own caching strategy.

  _(naive!) Example_

      @impl true
      def info_call(conn) do
        path = construct_cache_path(conn)

        if File.exists?(path) do
          {:stop, Plug.Conn.send_file(conn, 200, path)}
        else
          {:continue, conn}
        end
      end

      @impl true
      def info_response(conn, info) do
        path = construct_cache_path(conn)

        path
        |> Path.dirname()
        |> File.mkdir_p!()

        File.write!(path, Jason.encode!(data))

        {:stop, send_file(conn, 200, path)}
      end

      defp construct_cache_path(conn) do
        "/tmp/\#{Path.join(conn.path_info)}"
      end
  """
  @callback info_call(conn :: Conn.t()) :: {:continue, Conn.t()} | {:stop, Conn.t()}

  @doc """
  __Required__ callback function triggered on information requests (`info.json`), that maps the given _identifier_ to an
  image file.

  ## Returns

  - `{:ok, info_metadata}` on success, where `info_metadata` is a `IIIFImagePlug.V3.InfoRequestMetadata` struct.
  - `{:error, request_error}` otherwise, where `request_error` is a `IIIFImagePlug.V3.RequestError` struct.

  ## Example

      def info_metadata(identifier) do
        MyApp.ContextModule.get_image_metadata(identifier)
        |> case do
          %{path: path, rights_statement: rights} ->
            {
              :ok,
              %IIIFImagePlug.V3.InfoRequestMetadata{
                path: path,
                rights: rights
              }
            }
          {:error, :not_found} ->
            {
              :error,
              %IIIFImagePlug.V3.RequestError{
                status_code: 404,
                msg: :not_found
              }
            }
        end
      end
  """
  @callback info_metadata(identifier :: String.t()) ::
              {:ok, InfoRequestMetadata.t()} | {:error, RequestError.t()}

  @doc """
  __Optional__ callback function that gets triggered right before the `info.json` gets sent.

  This can be used in conjunction with `c:IIIFImagePlug.V3.info_call/1` to implement your
  own caching strategy.
  """
  @callback info_response(conn :: Conn.t(), info :: map()) ::
              {:continue, Conn.t()} | {:stop, Conn.t()}

  @doc """
  __Optional__ callback function that gets triggered at the start of each for an image data request, before
  any processing is done.

  If you want the plug to continue processing the information request, return `{:continue, conn}`,
  otherwise you might instruct the plug to stop further processing by returning `{:stop, conn}`.
  This can be used in conjunction with `c:IIIFImagePlug.V3.data_response/1` to implement your
  own caching strategy.

  _(naive!) Example_

      @impl true
      def data_call(conn) do
        path = construct_cache_path(conn)

        if File.exists?(path) do
          {:stop, Plug.Conn.send_file(conn, 200, path)}
        else
          {:continue, conn}
        end
      end

      @impl true
      def data_metadata(identifier), do: DefaultPlug.data_metadata(identifier)

      @impl true
      def data_response(%Plug.Conn{} = conn, image, _format) do
        path = construct_cache_path(conn)

        path
        |> Path.dirname()
        |> File.mkdir_p!()

        Vix.Vips.Image.write_to_file(image, path)

        {:stop, send_file(conn, 200, path)}
      end
  """
  @callback data_call(conn :: Conn.t()) :: {:continue, Conn.t()} | {:stop, Conn.t()}

  @doc """
  __Required__ callback function triggered on image data requests, that maps the given _identifier_ to an
  image file.

  ## Returns

  - `{:ok, data_metadata}` on success, where `data_metadata` is a `IIIFImagePlug.V3.DataRequestMetadata` struct.
  - `{:error, request_error}` otherwise, where `request_error` is a `IIIFImagePlug.V3.RequestError` struct.

  ## Example

      def data_metadata(identifier) do
        MyApp.ContextModule.get_image_path(identifier)
        |> case do
          {:ok, path} ->
            {
              :ok,
              %IIIFImagePlug.V3.DataRequestMetadata{
                path: path,
                response_headers: [
                  {"cache-control", "public, max-age=31536000, immutable"}
                ]
              }
            }
          {:error, :not_found} ->
            {
              :error,
              %IIIFImagePlug.V3.RequestError{
                status_code: 404,
                msg: :not_found
              }
            }
        end
      end
  """
  @callback data_metadata(identifier :: String.t()) ::
              {:ok, DataRequestMetadata.t()} | {:error, RequestError.t()}

  @doc """
  __Optional__ callback function that is triggered right before the final image gets rendered and sent.
  """
  @callback data_response(conn :: Conn.t(), image :: Image.t(), format :: atom()) ::
              {:continue, Conn.t()} | {:stop, Conn.t()}

  @doc """
  __Optional__ callback function to override the `:scheme` ("http" or "https") evaluated from the `Plug.Conn`, useful if your Elixir app runs behind a
  proxy.

  ## Example

      def scheme(), do: "https"
  """
  @callback scheme() :: String.t() | nil

  @doc """
  __Optional__ callback function to override the `:host` evaluated from the `Plug.Conn`, useful if your Elixir app runs behind a proxy.

  ## Example

      def host(), do: "images.example.org"
  """
  @callback host() :: String.t() | nil

  @doc """
  __Optional__ callback function to override the `:port` evaluated from the `Plug.Conn`, useful if your Elixir app runs behind a proxy.

  ## Example

      def port(), do: 1337
  """
  @callback port() :: pos_integer() | nil

  @doc """
  __Optional__ callback function that lets you override the default plug error response.

  ## Examples

  __Default implementation__

  The default response for all errors is defined as follows:

      def send_error(conn, status_code, msg) do
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          status_code,
          Jason.encode!(%{error: msg})
        )
      end


  __Rewriting 404 for data requests to serve a fallback image__

  You can pattern match on specific `conn`, `status_code` or `msg` to overwrite specific cases.

  One use case might be sending your own placeholder image instead of the JSON for failed data requests.

  First customize your `data_metadata/1` implementation with a specific message (you do not want
  to return an image on a failed `info.json` request):

      def data_metadata(identifier) do
        MyApp.ContextModule.get_image_path(identifier)
        |> case do
          {:ok, path} ->
            (...)
          {:error, :not_found} ->
            {
              :error,
              %IIIFImagePlug.V3.RequestError{
                status_code: 404,
                msg: :data_metadata_not_found
              }
            }
        end
      end

  Then add a custom `send_error/3` that picks up on the status code and message you defined:

      def send_error(conn, 404, :data_metadata_not_found) do
        Plug.Conn.send_file(conn, 404, "\#{Application.app_dir(:my_app)}/images/not_found.webp")
      end

  For all errors that do not match the pattern, the plug will be falling back to the default implementation
  shown above.

  __Rewriting errors generated by the plug__

  This also works for errors the plug generates interally:

      def send_error(conn, 400, :invalid_rotation) do
        requested_rotation = MyApp.extract_iiif_parameter(conn, :rotation)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          400,
          Jason.encode!(%{error: "Your rotation parameter '\#{requested_rotation}' is invalid!"})
        )
      end
  """
  @callback send_error(
              conn :: Conn.t(),
              status_code :: number(),
              msg :: atom()
            ) :: Conn.t()

  @optional_callbacks data_call: 1, data_response: 3, info_call: 1, info_response: 2

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

      def send_error(%Conn{} = conn, status_code, msg) do
        IIIFImagePlug.V3.send_error(conn, status_code, msg)
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
      def send_error(%Conn{} = conn, status_code, msg) do
        IIIFImagePlug.V3.send_error(conn, status_code, msg)
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
        %Plug.Conn{path_info: [_identifier, "info.json"]} = conn,
        %Options{} = options,
        module
      ) do
    if function_exported?(module, :info_call, 1) do
      case module.info_call(conn) do
        {:continue, conn} ->
          handle_info_metadata(conn, options, module)

        {:stop, conn} ->
          conn
      end
    else
      handle_info_metadata(conn, options, module)
    end
  end

  def call(
        %Plug.Conn{path_info: [_identifier, _region, _size, _rotation, _quality_and_format]} =
          conn,
        %Options{} = options,
        module
      ) do
    if function_exported?(module, :data_call, 1) do
      case module.data_call(conn) do
        {:continue, conn} ->
          handle_data_metadata(conn, options, module)

        {:stop, conn} ->
          conn
      end
    else
      handle_data_metadata(conn, options, module)
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

  defp handle_info_metadata(
         %Plug.Conn{path_info: [identifier, _rest]} = conn,
         %Options{} = options,
         module
       ) do
    case Info.generate_image_info(conn, identifier, options, module) do
      {:ok, {conn, info}} ->
        if function_exported?(module, :info_response, 2) do
          module.info_response(conn, info)
        else
          {:continue, conn}
        end
        |> case do
          {:continue, conn} ->
            conn
            |> put_resp_content_type("application/ld+json")
            |> send_resp(200, Jason.encode!(info))

          {:stop, conn} ->
            conn
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
    end
  end

  @streamable ["jpg", "webp", "gif", "png"]

  defp handle_data_metadata(
         %Plug.Conn{
           path_info: [identifier, region, size, rotation, quality_and_format]
         } = conn,
         %Options{
           temp_dir: temp_dir,
           format_options: format_options
         } = options,
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
        # Use the requested format for content-type (since that's what we're delivering)
        conn = put_resp_content_type_from_format(conn, format)

        format_as_atom = String.to_existing_atom(format)

        additional_format_options = Map.get(format_options, format_as_atom, [])

        if function_exported?(module, :data_response, 3) do
          module.data_response(conn, image, format_as_atom)
        else
          {:continue, conn}
        end
        |> case do
          {:continue, conn} ->
            cond do
              format not in @streamable and temp_dir == :buffer ->
                send_buffered(conn, image, format, additional_format_options)

              format not in @streamable ->
                prefix = :crypto.strong_rand_bytes(8) |> Base.url_encode64() |> binary_part(0, 8)

                file_name =
                  "#{prefix}_#{quality_and_format}"

                send_temporary_file(
                  conn,
                  image,
                  Path.join(temp_dir, file_name),
                  additional_format_options
                )

              true ->
                send_stream(conn, image, format, additional_format_options)
            end

          {:stop, conn} ->
            conn
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

  defp send_buffered(conn, %Image{} = image, format, format_options) do
    {:ok, buffer} = Image.write_to_buffer(image, ".#{format}", format_options)

    send_resp(conn, 200, buffer)
  end

  defp send_temporary_file(conn, %Image{} = image, file_path, format_options) do
    parent = self()

    spawn(fn ->
      Process.monitor(parent)

      receive do
        {:DOWN, _ref, :process, _pid, _reason} ->
          File.rm(file_path)
      end
    end)

    Image.write_to_file(image, file_path, format_options)

    send_file(conn, 200, file_path)
  end

  defp send_stream(conn, %Image{} = image, format, format_options) do
    stream = Image.write_to_stream(image, ".#{format}", format_options)

    conn = send_chunked(conn, 200)

    Enum.reduce_while(stream, conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  defp put_resp_content_type_from_format(conn, format) do
    # Only set content-type if not already set by response_headers
    case get_resp_header(conn, "content-type") do
      [] ->
        content_type = format_to_content_type(format)
        put_resp_content_type(conn, content_type)

      _ ->
        conn
    end
  end

  defp format_to_content_type(format) do
    case String.downcase(format) do
      "jpg" -> "image/jpeg"
      "jpeg" -> "image/jpeg"
      "png" -> "image/png"
      "gif" -> "image/gif"
      "webp" -> "image/webp"
      "svg" -> "image/svg+xml"
      "heif" -> "image/heif"
      "heic" -> "image/heif"
      "tif" -> "image/tiff"
      "tiff" -> "image/tiff"
      "bmp" -> "image/bmp"
      "avif" -> "image/avif"
      _ -> "application/octet-stream"
    end
  end

  @doc false
  def send_error(conn, status_code, msg) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      status_code,
      Jason.encode!(%{error: msg})
    )
  end

  @doc false
  def scheme(), do: nil

  @doc false
  def host(), do: nil

  @doc false
  def port(), do: nil
end
