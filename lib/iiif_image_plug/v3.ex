defmodule IIIFImagePlug.V3 do
  @behaviour Plug

  import Plug.Conn

  alias IiifImagePlug.V3.Info

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
        %Settings{status_callbacks: status_callbacks} = settings
      ) do
    case Info.evaluate(identifier, settings) do
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

      pages =
        if page_count > 1 do
          last_page = page_count - 1

          0..last_page
          |> Enum.map(fn page ->
            {:ok, page_image} = Image.new_from_file(path, page: page)

            width = Image.width(page_image)
            height = Image.height(page_image)

            {page_image, width, height}
          end)
        else
          []
        end

      apply_operations(file, region, size, rotation, quality, settings, pages)
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
         %Settings{} = settings,
         []
       )
       when is_binary(region) and is_binary(size) and is_binary(rotation) and
              quality in [:default, :color, :gray, :bitonal] do
    with %Region.ExtractArea{} = area <- Region.parse(input_file, region),
         %Image{} = applied_region <- Region.apply(input_file, area),
         %Size.Scaling{} = scaling <- Size.parse(applied_region, size, settings),
         %Image{} = applied_scaling <- Size.apply(applied_region, scaling),
         average <-
           (fn ->
              if quality == :bitonal do
                Vix.Vips.Operation.avg!(applied_scaling)
              else
                nil
              end
            end).(),
         %Rotation.Rotation{} = rotation <- Rotation.parse(rotation),
         %Image{} = applied_rotation <- Rotation.apply(applied_scaling, rotation),
         %Image{} = applied_quality <- Quality.apply(applied_rotation, quality, average) do
      applied_quality
    else
      error ->
        error
    end
  end

  # defp apply_operations(
  #        %Image{} = input_file,
  #        region,
  #        size,
  #        rotation,
  #        quality,
  #        %Settings{} = settings,
  #        pages
  #      )
  #      when is_binary(region) and is_binary(size) and is_binary(rotation) and
  #             quality in [:default, :color, :gray, :bitonal] do
  #   rotation = Rotation.parse(rotation)
  #   region_applied = Region.parse_and_apply(input_file, URI.decode(region))

  #   result =
  #     Size.parse(region_applied, URI.decode(size), settings)
  #     |> case do
  #       %Scaling{scale: scale, vscale: vscale} = scaling ->
  #         IO.inspect(Image.width(region_applied))
  #         IO.inspect(Image.height(region_applied))
  #         IO.inspect(scaling)

  #         if pages != [] do
  #           Enum.map(pages, fn {page, width, height} ->
  #             {page, %Scaling{scale: width / Image.width(input_file)}}
  #           end)
  #           |> Enum.filter(fn {_page, %Scaling{scale: page_scale}} ->
  #             scale < page_scale
  #           end)
  #           |> IO.inspect()
  #           |> Enum.min_by(fn {_page, %Scaling{scale: scale}} ->
  #             scale
  #           end)
  #           |> IO.inspect()
  #           |> case do
  #             {page, %Scaling{scale: page_scale}} ->
  #               adjusted_scale = scale / page_scale

  #               IO.inspect(Image.width(page))
  #               IO.inspect(Image.height(page))
  #               adjusted_image = Operation.resize!(page, adjusted_scale) |> IO.inspect()

  #               IO.inspect(Image.width(adjusted_image))
  #               IO.inspect(Image.height(adjusted_image))

  #               IO.inspect("using page")
  #               adjusted_image

  #             _ ->
  #               scaling_applied =
  #                 if vscale do
  #                   Operation.resize!(region_applied, scale, vscale: vscale)
  #                 else
  #                   Operation.resize!(region_applied, scale)
  #                 end

  #               IO.inspect(Image.width(scaling_applied))
  #               IO.inspect(Image.height(scaling_applied))
  #               IO.inspect("using default")
  #               scaling_applied
  #           end
  #         else
  #           scaling_applied =
  #             if vscale do
  #               Operation.resize!(region_applied, scale, vscale: vscale)
  #             else
  #               Operation.resize!(region_applied, scale)
  #             end

  #           IO.inspect(Image.width(scaling_applied))
  #           IO.inspect(Image.height(scaling_applied))
  #           IO.inspect("using default")
  #           scaling_applied
  #         end

  #       error ->
  #         error
  #     end

  #   average =
  #     case result do
  #       %Image{} = image ->
  #         Vix.Vips.Operation.avg!(image)

  #       _ ->
  #         nil
  #     end

  #   result
  #   |> Rotation.parse_and_apply(rotation)
  #   |> Quality.parse_and_apply(quality, average)
  # end

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
