defmodule IIIFImagePlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.Parameters.{
    Quality,
    Region,
    Rotation,
    Size
  }

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
      :identifier_to_path_callback
    ]
    defstruct [
      :scheme,
      :server,
      :prefix,
      :max_width,
      :max_height,
      :max_area,
      :identifier_to_path_callback
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
          raise("Missing callback used to construct file path from identifier.")
    }
  end

  def call(
        %Plug.Conn{path_info: [identifier, "info.json"]} = conn,
        %Opts{identifier_to_path_callback: path_callback} = opts
      ) do
    path = path_callback.(identifier)

    Image.new_from_file(path)
    |> case do
      {:ok, file} ->
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

      {:error, _msg} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          404,
          Jason.encode!(%{
            description: "Could not find file matching '#{identifier}'."
          })
        )
    end
  end

  def call(
        %Plug.Conn{
          path_info: [identifier, region, size, rotation, quality_and_format]
        } = conn,
        %Opts{identifier_to_path_callback: path_callback} = opts
      ) do
    path = path_callback.(identifier)

    with {
           :file_opened,
           {:ok, file}
         } <- {
           :file_opened,
           Image.new_from_file(path)
         },
         {
           :quality_and_format_parsed,
           %{quality: quality, format: format}
         } <- {
           :quality_and_format_parsed,
           parse_quality_and_format(quality_and_format)
         } do
      file
      |> Region.apply(URI.decode(region))
      |> Size.apply(URI.decode(size), opts)
      |> Rotation.apply(rotation)
      |> Quality.apply(quality)
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
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: msg}))
      end
    else
      {:file_opened, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          404,
          Jason.encode!(%{
            description: "Could not find file matching '#{identifier}'."
          })
        )

      {:quality_and_format_parsed, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          400,
          Jason.encode!(%{
            description:
              "Could not find parse valid quality and format from '#{quality_and_format}'."
          })
        )
    end
  end

  def call(
        conn,
        _opts
      ) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      400,
      Jason.encode!(%{
        description: "Invalid request scheme."
      })
    )
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
end
