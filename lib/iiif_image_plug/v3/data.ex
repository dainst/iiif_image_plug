defmodule IIIFImagePlug.V3.Data do
  alias IIIFImagePlug.V3.Size.Scaling
  alias IIIFImagePlug.V3.Region.ExtractArea
  alias IIIFImagePlug.V3.Quality
  alias IIIFImagePlug.V3.Rotation
  alias IIIFImagePlug.V3.Size
  alias IIIFImagePlug.V3.Region
  alias IIIFImagePlug.V3.Settings
  alias Vix.Vips.Image

  def process_basic(
        %Image{} = input_file,
        region,
        size,
        rotation,
        quality,
        %Settings{} = settings
      )
      when is_binary(region) and is_binary(size) and is_binary(rotation) and
             quality in [:default, :color, :gray, :bitonal] do
    with %ExtractArea{} = area <- Region.parse(input_file, region),
         %Image{} = applied_region <- Region.apply(input_file, area),
         %Size.Scaling{} = scaling <- Size.parse(applied_region, size, settings),
         %Image{} = applied_scaling <- Size.apply(applied_region, scaling),
         average <- calculate_average(applied_scaling, quality),
         %Rotation.Rotation{} = rotation <- Rotation.parse(rotation),
         %Image{} = applied_rotation <- Rotation.apply(applied_scaling, rotation),
         %Image{} = applied_quality <- Quality.apply(applied_rotation, quality, average) do
      applied_quality
    else
      error ->
        error
    end
  end

  def process_page_optimized(
        %Image{} = input_file,
        region,
        size,
        rotation,
        quality,
        %Settings{} = settings,
        pages
      )
      when is_binary(region) and is_binary(size) and is_binary(rotation) and
             quality in [:default, :color, :gray, :bitonal] and is_list(pages) do
    with %Region.ExtractArea{} = area <- Region.parse(input_file, region),
         %Image{} = applied_base_region <- Region.apply(input_file, area),
         %Size.Scaling{} = scaling <- Size.parse(applied_base_region, size, settings),
         %Image{} = applied_base_scaling <- Size.apply(applied_base_region, scaling),
         %Image{} = applied_page_optimized <-
           page_optimize(area, scaling, input_file, applied_base_scaling, pages),
         average <- calculate_average(applied_page_optimized, quality),
         %Rotation.Rotation{} = rotation <- Rotation.parse(rotation),
         %Image{} = applied_rotation <- Rotation.apply(applied_page_optimized, rotation),
         %Image{} = final <- Quality.apply(applied_rotation, quality, average) do
      final
    else
      error ->
        error
    end
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

  defp page_optimize(
         _area,
         _scale,
         _base_image,
         _base_image_transform,
         _pages
       ) do
    raise "Page optimization with vscale not implemented yet."
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
