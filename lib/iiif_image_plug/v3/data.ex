defmodule IIIFImagePlug.V3.Data do
  alias Vix.Vips.{
    Image,
    Operation
  }

  alias IIIFImagePlug.V3.Data.{
    Size,
    Size.Scaling,
    Region,
    Region.ExtractArea,
    Rotation,
    Quality
  }

  @moduledoc """
  Produces image data based on the given IIIF parameters and Plug settings.
  """

  @doc """
  Get a transformed version of the image defined by `identifier` and the other provided parameters,
  validated against the plug's settings.

  Returns
  - `{%Vix.Vips.Image{}, format}` on success, where format is one of the preferred or extra format atoms defined
  in the plug settings.
  - `{:error, reason}` if a parameter was invalid.
  """
  def get(
        identifier,
        region_param,
        size_param,
        rotation_param,
        quality_and_format_param,
        settings,
        module
      ) do
    {:ok, path} = module.identifier_path(identifier)

    with {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <- {:file_opened, Image.new_from_file(path)},
         {:file_opened, {:ok, {file, _}}} <- {:file_opened, Operation.autorot(file)},
         {:quality_and_format_parsed, %{quality: quality, format: format}} <-
           {:quality_and_format_parsed, Quality.parse(quality_and_format_param, settings)} do
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
          height = Image.height(file)

          0..last_page
          |> Enum.map(fn page_count ->
            {:ok, page_image} = Image.new_from_file(path, page: page_count)

            page_width = Image.width(page_image)
            page_height = Image.height(page_image)
            {page_image, %Scaling{scale: page_width / width, vscale: page_height / height}}
          end)
        else
          []
        end

      case transform(file, region_param, size_param, rotation_param, quality, pages, settings) do
        %Image{} = image ->
          {image, format}

        error ->
          error
      end
    else
      {:file_exists, false} ->
        {:error, :no_file}

      {:file_opened, _} ->
        {:error, :no_image_file}

      {:quality_and_format_parsed, _} ->
        {:error, :invalid_quality_and_format}
    end
  end

  defp transform(
         file,
         region_param,
         size_param,
         rotation_param,
         quality_param,
         pages,
         settings
       ) do
    with %Region.ExtractArea{} = area <- Region.parse(file, region_param),
         %Rotation.Rotation{} = rotation <- Rotation.parse(rotation_param),
         %Image{} = image <- Region.apply(file, area),
         # Scaling factor can only be evaluated based off the selected region in some cases.
         %Size.Scaling{} = scaling <- Size.parse(image, size_param, settings),
         %Image{} = image <- Size.apply(image, scaling),
         %Image{} = image <- page_optimize(area, scaling, file, image, pages),
         # Average is used for creating bitonal images, and we calculate it specifically for the
         # selected region.
         average <- calculate_average(image, quality_param),
         %Image{} = image <- Rotation.apply(image, rotation),
         %Image{} = final <- Quality.apply(image, quality_param, average) do
      final
    else
      error ->
        error
    end
  end

  defp page_optimize(
         _area,
         _scaling,
         _source_image,
         %Image{} = unoptimized_transform,
         pages
       )
       when pages == [] do
    # No image pages, nothing to optimize.
    unoptimized_transform
  end

  defp page_optimize(
         _area,
         %Scaling{scale: 1, vscale: nil},
         _source_image,
         %Image{} = unoptimized_transform,
         _pages
       ) do
    # No scaling requested, nothing to optimize.
    unoptimized_transform
  end

  defp page_optimize(
         %ExtractArea{} = requested_area,
         %Scaling{scale: requested_scale, vscale: requested_vscale},
         %Image{} = source_image,
         %Image{} = unoptimized_transform,
         pages
       )
       when is_list(pages) do
    pages
    |> Stream.filter(fn {_page, %Size.Scaling{scale: page_scale, vscale: page_vscale}} ->
      if requested_vscale do
        requested_scale < page_scale and requested_vscale < page_vscale
      else
        requested_scale < page_scale
      end
    end)
    |> Enum.min_by(
      fn {_page, %Size.Scaling{scale: scale}} ->
        scale
      end,
      fn -> nil end
    )
    |> case do
      {page, %Size.Scaling{scale: page_scale, vscale: page_vscale}} ->
        adjusted_region =
          if full_region_requested?(source_image, requested_area) do
            page
          else
            Region.apply(
              page,
              %ExtractArea{
                left: (requested_area.left * page_scale) |> trunc(),
                top: (requested_area.top * page_vscale) |> trunc(),
                width: (requested_area.width * page_scale) |> trunc(),
                height: (requested_area.height * page_vscale) |> trunc()
              }
            )
          end

        adjusted_scale = requested_scale / page_scale

        adjusted_vscale =
          if requested_vscale do
            requested_vscale / page_vscale
          else
            nil
          end

        Size.apply(adjusted_region, %Scaling{scale: adjusted_scale, vscale: adjusted_vscale})

      nil ->
        # None of the lower resolution page scales was higher than the requested one, so we use the
        # unoptimized transformation.
        unoptimized_transform
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
