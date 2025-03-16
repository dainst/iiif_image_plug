defmodule IIIFImagePlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias IIIFImagePlug.V3.Transformer
  alias Vix.Vips.Image

  require Logger

  @moduledoc """
  Documentation for `IIIFImagePlug`.
  """

  defmodule Opts do
    @enforce_keys [
      :scheme,
      :server,
      :prefix,
      :max_width,
      :max_height,
      :max_area,
      :identifier_to_path_callback,
      :status_callbacks
    ]
    defstruct [
      :scheme,
      :server,
      :prefix,
      :max_width,
      :max_height,
      :max_area,
      :identifier_to_path_callback,
      :status_callbacks
    ]
  end

  def init(opts) do
    default_dimension = 10000

    %Opts{
      scheme: opts[:scheme] || :http,
      server: opts[:server] || "localhost",
      prefix: opts[:prefix] || "/",
      max_width: opts[:max_width] || default_dimension,
      max_height: opts[:max_height] || default_dimension,
      max_area: opts[:max_area] || default_dimension * default_dimension,
      identifier_to_path_callback:
        opts.identifier_to_path_callback ||
          raise("Missing callback used to construct file path from identifier."),
      status_callbacks: opts[:status_callbacks] || %{}
    }
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        %Opts{identifier_to_path_callback: path_callback, status_callbacks: status_callbacks} =
          opts
      ) do
    path = path_callback.(identifier)

    with {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <- {:file_opened, Image.new_from_file(path)} do
      conn
      |> put_resp_content_type("application/ld+json")
      |> send_resp(
        200,
        %{
          "@context": "http://iiif.io/api/image/3/context.json",
          id: "#{opts.scheme}://#{opts.server}#{opts.prefix}/#{identifier}",
          type: "ImageServer3",
          protocol: "#{opts.scheme}://#{opts.server}/#{opts.prefix}",
          width: Image.width(file),
          height: Image.height(file),
          profile: "level0",
          maxHeight: opts.max_height,
          maxWidth: opts.max_width,
          maxArea: opts.max_area
        }
        |> Jason.encode!()
      )
    else
      {:file_exists, false} ->
        send_error(
          conn,
          404,
          %{
            description: "Could not find file matching '#{identifier}'."
          },
          status_callbacks
        )

      {:file_opened, _} ->
        send_error(
          conn,
          500,
          %{
            description: "Could not open image file matching '#{identifier}'."
          },
          status_callbacks
        )
    end
  end

  def call(
        %Plug.Conn{
          path_info: [identifier, region, size, rotation, quality_and_format]
        } = conn,
        %Opts{identifier_to_path_callback: path_callback, status_callbacks: status_callbacks} =
          opts
      ) do
    path = path_callback.(identifier)

    with {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <- {:file_opened, Image.new_from_file(path)},
         {:quality_and_format_parsed, %{quality: quality, format: format}} <-
           {:quality_and_format_parsed, parse_quality_and_format(quality_and_format)} do
      Transformer.start(file, region, size, rotation, quality, opts)
      |> case do
        %Image{} = transformed ->
          stream = Image.write_to_stream(transformed, format)

          conn = send_chunked(conn, 200)

          Enum.reduce_while(stream, conn, fn data, conn ->
            case chunk(conn, data) do
              {:ok, conn} -> {:cont, conn}
              {:error, :closed} -> {:halt, conn}
            end
          end)

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
            description: "Could not find file matching '#{identifier}'."
          },
          status_callbacks
        )

      {:file_opened, _} ->
        send_error(
          conn,
          500,
          %{
            description: "Could not open image file matching '#{identifier}'."
          },
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
        %Opts{status_callbacks: callbacks}
      ) do
    send_error(conn, 400, %{description: "Invalid request scheme."}, callbacks)
  end

  defp parse_quality_and_format(quality_and_format) when is_binary(quality_and_format) do
    String.split(quality_and_format, ".")
    |> case do
      [quality, format]
      when quality in ["default", "color", "gray", "bitonal"] and
             format in ["jpg", "tif", "png", "webp"] ->
        %{
          quality: String.to_existing_atom(quality),
          format: ".#{format}"
        }

      _ ->
        :error
    end
  end

  def send_error(conn, code, info, status_callbacks)
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
