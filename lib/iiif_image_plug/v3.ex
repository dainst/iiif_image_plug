defmodule IIIFImagePlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias IIIFImagePlug.V3.{
    Quality,
    Region,
    Rotation,
    Size
  }

  alias Vix.Vips.Image

  require Logger

  @moduledoc """
  Documentation for `IIIFImagePlug`.
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
        %Settings{
          identifier_to_path_callback: path_callback,
          status_callbacks: status_callbacks,
          identifier_to_rights_callback: rights_callback,
          identifier_to_part_of_callback: part_of_callback,
          identifier_to_see_also_callback: see_also_callback,
          identifier_to_service_callback: service_callback
        } =
          settings
      ) do
    path = path_callback.(identifier)

    with {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <-
           {:file_opened, Image.new_from_file(path)} do
      info =
        %{
          "@context": "http://iiif.io/api/image/3/context.json",
          id:
            "#{settings.scheme}://#{settings.host}#{if settings.port do
              ":#{settings.port}"
            else
              ""
            end}#{settings.prefix}/#{identifier}",
          type: "ImageServer3",
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
        |> maybe_add_callback_data(identifier, rights_callback, :rights)
        |> maybe_add_callback_data(identifier, see_also_callback, :seeAlso)
        |> maybe_add_callback_data(identifier, part_of_callback, :partOf)
        |> maybe_add_callback_data(identifier, service_callback, :service)

      conn
      |> put_resp_content_type("application/ld+json")
      |> send_resp(200, Jason.encode!(info))
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
           {:quality_and_format_parsed, parse_quality_and_format(quality_and_format, settings)} do
      apply_operations(file, region, size, rotation, quality, settings)
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

  defp apply_operations(
         %Image{} = input_file,
         region,
         size,
         rotation,
         quality,
         %Settings{} = opts
       )
       when is_binary(region) and is_binary(size) and is_binary(rotation) and
              quality in [:default, :color, :gray, :bitonal] do
    result =
      input_file
      |> Region.parse_and_apply(URI.decode(region))
      |> Size.parse_and_apply(URI.decode(size), opts)

    average =
      case result do
        %Image{} = image ->
          Vix.Vips.Operation.avg!(image)

        _ ->
          nil
      end

    result
    |> Rotation.parse_and_apply(rotation)
    |> Quality.parse_and_apply(quality, average)
  end

  defp parse_quality_and_format(quality_and_format, %Settings{
         preferred_formats: preferred_formats,
         extra_formats: extra_formats
       })
       when is_binary(quality_and_format) do
    String.split(quality_and_format, ".")
    |> case do
      [quality, format]
      when quality in ["default", "color", "gray", "bitonal"] and
             is_binary(format) ->
        if format in Stream.map(preferred_formats ++ extra_formats, &Atom.to_string/1) do
          %{
            quality: String.to_existing_atom(quality),
            format: format
          }
        end

      _ ->
        :error
    end
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

  defp maybe_add_callback_data(info, _identifier, nil, _key) do
    info
  end

  defp maybe_add_callback_data(info, identifier, callback, key) do
    callback.(identifier)
    |> case do
      {:ok, result} ->
        Map.put(info, key, result)

      _ ->
        info
    end
  end
end
