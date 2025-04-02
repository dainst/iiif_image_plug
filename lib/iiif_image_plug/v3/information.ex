defmodule IIIFImagePlug.V3.Information do
  alias Plug.Conn
  alias Vix.Vips.Image

  alias IIIFImagePlug.V3
  alias IIIFImagePlug.V3.Settings

  @moduledoc """
  Produces image metadata (info.json).
  """

  @doc """
  Get the IIIF `info.json` for the image defined by `identifier` with respect to the plug's settings.

  Returns
  - `info` as an Elixir map on success.
  - `{:error, :no_file}` if the identifier did not point to a file.
  - `{:error, :no_image_file}` if the identifier did not point to a file.
  """
  def get(
        identifier,
        %Conn{} = conn,
        %Settings{
          identifier_to_path_callback: path_callback,
          identifier_to_rights_callback: rights_callback,
          identifier_to_part_of_callback: part_of_callback,
          identifier_to_see_also_callback: see_also_callback,
          identifier_to_service_callback: service_callback
        } = settings
      ) do
    path = path_callback.(identifier)

    with {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <-
           {:file_opened, Image.new_from_file(path)} do
      {
        :ok,
        %{
          "@context": "http://iiif.io/api/image/3/context.json",
          id: "#{V3.construct_id_url(conn)}/#{identifier}",
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
        |> maybe_add_callback_data(identifier, rights_callback, :rights)
        |> maybe_add_callback_data(identifier, see_also_callback, :seeAlso)
        |> maybe_add_callback_data(identifier, part_of_callback, :partOf)
        |> maybe_add_callback_data(identifier, service_callback, :service)
        |> maybe_add_sizes(file, path)
      }
    else
      {:file_exists, false} ->
        {:error, :no_file}

      {:file_opened, _} ->
        {:error, :no_image_file}
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
            heigh: height
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
