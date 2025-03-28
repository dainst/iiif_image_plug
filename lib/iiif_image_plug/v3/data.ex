defmodule IIIFImagePlug.V3.Data do
  alias IIIFImagePlug.V3.Size.Scaling
  alias IIIFImagePlug.V3.Region.ExtractArea
  alias IIIFImagePlug.V3.Quality
  alias IIIFImagePlug.V3.Rotation
  alias IIIFImagePlug.V3.Size
  alias IIIFImagePlug.V3.Region
  alias IIIFImagePlug.V3.Settings
  alias Vix.Vips.Image

  def process(
        identifier,
        region,
        size,
        rotation,
        quality_and_format,
        %Settings{
          identifier_to_path_callback: path_callback
        } = settings
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

          width = Image.width(file)

          0..last_page
          |> Enum.map(fn page ->
            {:ok, page_image} = Image.new_from_file(path, page: page)

            page_width = Image.width(page_image)

            {page_image, %Scaling{scale: page_width / width}}
          end)
        else
          []
        end

      case pipeline_full(file, region, size, rotation, quality, pages, settings) do
        %Image{} = image ->
          {image, format}

        error ->
          error
      end
    end
  end

  defp pipeline_full(
         file,
         region_param,
         size_param,
         rotation_param,
         quality_param,
         pages,
         settings
       ) do
    with %Region.ExtractArea{} = area <- Region.parse(file, region_param),
         %Image{} = applied_base_region <- Region.apply(file, area),
         %Size.Scaling{} = scaling <- Size.parse(applied_base_region, size_param, settings),
         %Image{} = applied_base_scaling <- Size.apply(applied_base_region, scaling),
         %Image{} = applied_page_optimized <-
           page_optimize(area, scaling, file, applied_base_scaling, pages),
         %Image{} = final <-
           pipeline_rotation_and_quality(applied_page_optimized, rotation_param, quality_param) do
      final
    else
      error ->
        error
    end
  end

  defp pipeline_rotation_and_quality(image, rotation_param, quality_param) do
    with average <- calculate_average(image, quality_param),
         %Rotation.Rotation{} = rotation <- Rotation.parse(rotation_param),
         %Image{} = image <- Rotation.apply(image, rotation),
         %Image{} = final <- Quality.apply(image, quality_param, average) do
      final
    else
      error -> error
    end
  end

  defp page_optimize(
         _area,
         _scaling,
         _base_image,
         base_image_transform,
         pages
       )
       when pages == [] do
    base_image_transform
  end

  defp page_optimize(
         _area,
         %Scaling{scale: 1, vscale: nil},
         base_image,
         _base_image_transform,
         _pages
       ) do
    base_image
  end

  defp page_optimize(
         %ExtractArea{} = requested_area,
         %Scaling{scale: requested_scale, vscale: requested_vscale},
         %Image{} = base_image,
         %Image{} = base_image_transformed,
         pages
       )
       when is_list(pages) do
    pages
    |> Stream.filter(fn {_page, %Size.Scaling{scale: page_scale}} ->
      requested_scale < page_scale
    end)
    |> Enum.min_by(
      fn {_page, %Size.Scaling{scale: scale}} ->
        scale
      end,
      fn -> nil end
    )
    |> case do
      {page, %Size.Scaling{scale: page_scale}} ->
        adjusted_region =
          if not full_region_requested?(base_image, requested_area) do
            adjusted_area =
              %ExtractArea{
                left: (requested_area.left * page_scale) |> trunc(),
                top: (requested_area.top * page_scale) |> trunc(),
                width: (requested_area.width * page_scale) |> trunc(),
                height: (requested_area.height * page_scale) |> trunc()
              }

            page
            |> Region.apply(adjusted_area)
          else
            page
          end

        adjusted_scale = requested_scale / page_scale

        adjusted_vscale =
          if requested_vscale do
            requested_vscale / page_scale
          else
            nil
          end

        Size.apply(adjusted_region, %Scaling{scale: adjusted_scale, vscale: adjusted_vscale})

      nil ->
        # None of the lower resolution page scales was higher than the requested one, so we use the
        # unoptimized transformation.
        base_image_transformed
    end
  end

  defp full_region_requested?(
         %Image{} = image,
         %ExtractArea{
           left: 0,
           top: 0,
           width: width,
           height: height
         }
       ) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    width == image_width and height == image_height
  end

  defp full_region_requested?(_, _) do
    false
  end

  defp calculate_average(image, :bitonal), do: Vix.Vips.Operation.avg!(image)
  defp calculate_average(_image, _quality), do: nil
end
