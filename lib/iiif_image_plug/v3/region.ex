defmodule IIIFImagePlug.V3.Region do
  @moduledoc false
  defmodule ExtractArea do
    @moduledoc false
    @enforce_keys [:left, :top, :width, :height]
    defstruct [:left, :top, :width, :height]
  end

  alias Vix.Vips.{
    Operation,
    Image
  }

  def parse(%Image{} = image, "full") do
    %ExtractArea{
      left: 0,
      top: 0,
      width: Image.width(image),
      height: Image.height(image)
    }
  end

  def parse(%Image{} = image, "square") do
    width = Image.width(image)
    height = Image.height(image)

    {left, top, width, height} =
      cond do
        width == height ->
          {0, 0, width, height}

        width > height ->
          {div(width - height, 2), 0, height, height}

        width < height ->
          {0, div(height - width, 2), width, width}
      end

    %ExtractArea{
      left: left,
      top: top,
      width: width,
      height: height
    }
  end

  def parse(%Image{} = image, "pct:" <> region_params) when is_binary(region_params) do
    String.replace(region_params, "pct:", "")
    |> String.split(",")
    |> case do
      [x_string, y_string, w_string, h_string] ->
        {
          Float.parse(x_string),
          Float.parse(y_string),
          Float.parse(w_string),
          Float.parse(h_string)
        }

      _ ->
        {:error, :invalid_region}
    end
    |> case do
      {
        {left, ""},
        {top, ""},
        {width, ""},
        {height, ""}
      }
      when left >= 0.0 and left <= 100.0 and top >= 0.0 and top <= 100.0 and width > 0.0 and
             width <= 100.0 and
             height > 0.0 and height <= 100.0 ->
        image_width = Image.width(image)
        image_height = Image.height(image)

        left_in_pixel = (image_width * (left / 100)) |> trunc()
        top_in_pixel = (image_height * (top / 100)) |> trunc()
        width_in_pixel = (image_width * (width / 100)) |> trunc()
        height_in_pixel = (image_height * (height / 100)) |> trunc()

        %ExtractArea{
          left: left_in_pixel,
          top: top_in_pixel,
          width: width_in_pixel,
          height: height_in_pixel
        }

      _ ->
        {:error, :invalid_region}
    end
  end

  def parse(%Image{} = image, region_params) when is_binary(region_params) do
    region_params
    |> String.split(",")
    |> case do
      [x_string, y_string, w_string, h_string] ->
        {
          Integer.parse(x_string),
          Integer.parse(y_string),
          Integer.parse(w_string),
          Integer.parse(h_string)
        }

      _ ->
        {:error, :invalid_region}
    end
    |> case do
      {
        {left, ""},
        {top, ""},
        {width, ""},
        {height, ""}
      }
      when left >= 0 and top >= 0 and width > 0 and height > 0 ->
        image_width = Image.width(image)
        image_height = Image.height(image)

        if left < image_width and top < image_height do
          width =
            if left + width > image_width do
              image_width - left
            else
              width
            end

          height =
            if top + height > image_height do
              image_height - top
            else
              height
            end

          %ExtractArea{
            left: left,
            top: top,
            width: width,
            height: height
          }
        else
          {:error, :invalid_region}
        end

      _ ->
        {:error, :invalid_region}
    end
  end

  def apply(%Image{} = image, %ExtractArea{left: 0, top: 0, width: width, height: height}) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    if image_width == width and image_height == height do
      image
    else
      Operation.extract_area!(image, 0, 0, width, height)
    end
  end

  def apply(%Image{} = image, %ExtractArea{left: left, top: top, width: width, height: height}) do
    Operation.extract_area!(image, left, top, width, height)
  end
end
