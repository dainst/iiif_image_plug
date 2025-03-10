defmodule IIIFPlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias Vix.Vips.Image

  alias Transformation.{
    Quality,
    Region,
    Rotation,
    Size
  }

  require Logger

  @moduledoc """
  Documentation for `IIIFPlug`.
  """

  defmodule Opts do
    @enforce_keys [:scheme, :server, :prefix, :max_width, :max_height, :max_area]
    defstruct [:scheme, :server, :prefix, :max_width, :max_height, :max_area]
  end

  def init(opts) do
    default_dimension = 10000

    %Opts{
      scheme: opts[:scheme] || :http,
      server: opts[:server] || "example.com",
      prefix: opts[:prefix] || "/",
      max_width: opts[:max_width] || default_dimension,
      max_height: opts[:max_height] || default_dimension,
      max_area: opts[:max_area] || default_dimension * default_dimension
    }
  end

  def call(%Plug.Conn{path_info: [identifier, "info.json"]} = conn, %Opts{} = opts) do
    Image.new_from_file(identifier)
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
        opts
      ) do
    case Image.new_from_file(identifier) do
      {:ok, file} ->
        %{quality: quality, format: format} =
          parse_quality_and_format(quality_and_format)

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
    end
  end

  @doc """
  Hello world.

  ## Examples

      iex> IIIFPlug.hello()
      :world

  """
  def hello do
    :world
  end
end
