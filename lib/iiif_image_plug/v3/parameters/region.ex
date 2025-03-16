defmodule IIIFImagePlug.V3.Transformer.Region do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def parse_and_apply(%Image{} = image, "full") do
    image
  end

  def parse_and_apply(%Image{} = image, "square") do
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

    Operation.extract_area!(image, left, top, width, height)
  end

  def parse_and_apply(%Image{} = image, "pct:" <> region_params) do
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
        width_in_pixel = (image_width * (left / 100)) |> trunc()
        height_in_pixel = (image_height * (top / 100)) |> trunc()

        __MODULE__.parse_and_apply(
          image,
          "#{left_in_pixel},#{top_in_pixel},#{width_in_pixel},#{height_in_pixel}"
        )

      _ ->
        {:error, :invalid_region}
    end
  end

  def parse_and_apply(%Image{} = image, region_params) when is_binary(region_params) do
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

          Operation.extract_area!(image, left, top, width, height)
        else
          {:error, :invalid_region}
        end

      _ ->
        {:error, :invalid_region}
    end
    |> dbg()
  end
end
