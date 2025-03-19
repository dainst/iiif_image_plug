defmodule IIIFImagePlug.V3.Size do
  alias Vix.Vips.{
    Operation,
    Image
  }

  alias IIIFImagePlug.V3.Settings

  def parse_and_apply(%Image{} = image, "max", %Settings{} = settings) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    image_area = image_width * image_height

    # Select the smallest factor that would scale the image to one of the plug's maxima.
    # We filter only for values < 1.
    # - If it is larger than 1, the image would get scaled up by the factor, we do not want that here (that would be "^max").
    # - If it is smaller than 1, the image will get scaled down.
    # - If all factors are larger than 1, all dimensions and the area fall within the plugs maxima and we fallback to a factor of 1 (no scaling).

    factor =
      Enum.min(
        [
          :math.sqrt(settings.max_area / image_area),
          settings.max_width / image_width,
          settings.max_height / image_height
        ]
        |> Enum.filter(fn val -> val < 1 end),
        fn ->
          1
        end
      )

    if factor == 1 do
      image
    else
      Operation.resize!(image, factor)
    end
  end

  def parse_and_apply(%Image{} = image, "^max", settings) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    image_area = image_width * image_height

    # Select the smallest factor that would scale the image to one of the plug's maxima.
    factor =
      Enum.min([
        :math.sqrt(settings.max_area / image_area),
        settings.max_width / image_width,
        settings.max_height / image_height
      ])

    Operation.resize!(image, factor)
  end

  def parse_and_apply(%Image{} = image, size_parameter, settings)
      when is_binary(size_parameter) do
    upscale? = String.starts_with?(size_parameter, "^")
    size_parameter = String.replace_leading(size_parameter, "^", "")

    maintain_ratio? = String.starts_with?(size_parameter, "!")
    size_parameter = String.replace_leading(size_parameter, "!", "")

    if String.starts_with?(size_parameter, "pct:") do
      size_parameter
      |> String.replace_leading("pct:", "")
      |> Integer.parse()
      |> case do
        {percent, ""} when percent >= 0 and upscale? ->
          requested_factor = percent / 100

          image_width = Image.width(image)
          image_height = Image.height(image)
          image_area = image_width * image_height

          valid_maximum_factor =
            Enum.min([
              :math.sqrt(settings.max_area / image_area),
              settings.max_width / image_width,
              settings.max_height / image_height
            ])

          factor =
            if requested_factor < valid_maximum_factor,
              do: requested_factor,
              else: valid_maximum_factor

          Operation.resize!(image, factor)

        {percent, ""} when percent > 100 ->
          {:error, :invalid_size}

        {percent, ""} when percent >= 0 ->
          Operation.resize!(image, percent / 100)

        _ ->
          {:error, :invalid_size}
      end
    else
      w_h = String.split(size_parameter, ",")

      apply_w_h_Transformer(image, w_h, upscale?, maintain_ratio?, settings)
    end
  end

  def parse_and_apply(error, _, _), do: error

  defp apply_w_h_Transformer(
         image,
         [w_parameter, ""],
         upscale?,
         _maintain_ratio?,
         %Settings{} = settings
       ) do
    Integer.parse(w_parameter)
    |> case do
      {w, ""} ->
        image_width = Image.width(image)

        cond do
          upscale? ->
            image_height = Image.height(image)
            image_area = image_width * image_height

            requested_factor = w / image_width

            valid_maximum_factor =
              Enum.min([
                :math.sqrt(settings.max_area / image_area),
                settings.max_width / image_width,
                settings.max_height / image_height
              ])

            factor =
              if requested_factor < valid_maximum_factor,
                do: requested_factor,
                else: valid_maximum_factor

            Operation.resize!(image, factor)

          w > image_width ->
            {:error, :invalid_size}

          true ->
            Operation.resize!(image, w / image_width)
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp apply_w_h_Transformer(
         image,
         ["", h_parameter],
         upscale?,
         _maintain_ratio?,
         %Settings{} = settings
       ) do
    Integer.parse(h_parameter)
    |> case do
      {h, ""} ->
        image_height = Image.height(image)

        cond do
          upscale? ->
            requested_factor = h / image_height
            image_width = Image.width(image)
            image_area = image_width * image_height

            valid_maximum_factor =
              Enum.min([
                :math.sqrt(settings.max_area / image_area),
                settings.max_width / image_width,
                settings.max_height / image_height
              ])

            factor =
              if requested_factor < valid_maximum_factor,
                do: requested_factor,
                else: valid_maximum_factor

            Operation.resize!(image, factor)

          h > image_height ->
            {:error, :invalid_size}

          true ->
            Operation.resize!(image, h / image_height)
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp apply_w_h_Transformer(
         image,
         [w_parameter, h_parameter],
         upscale?,
         maintain_ratio?,
         %Settings{} = settings
       ) do
    {Integer.parse(w_parameter), Integer.parse(h_parameter)}
    |> case do
      {{w, ""}, {h, ""}} ->
        image_width = Image.width(image)
        image_height = Image.height(image)

        cond do
          upscale? and maintain_ratio? ->
            valid_requested_factor =
              Enum.min([
                w / image_width,
                h / image_height
              ])

            valid_maximum_factor =
              Enum.min([
                :math.sqrt(image_width * image_height),
                settings.max_width / image_width,
                settings.max_height / image_height
              ])

            factor =
              if valid_requested_factor < valid_maximum_factor,
                do: valid_requested_factor,
                else: valid_maximum_factor

            Operation.resize!(image, factor)

          upscale? ->
            requested_width_factor = w / image_width
            requested_height_factor = h / image_height

            max_width_factor = settings.max_width / image_width
            max_height_factor = settings.max_height / image_height

            width_factor =
              if requested_width_factor < max_width_factor,
                do: requested_width_factor,
                else: max_width_factor

            height_factor =
              if requested_height_factor < max_height_factor,
                do: requested_height_factor,
                else: max_height_factor

            Operation.resize!(image, width_factor, vscale: height_factor)

          w > image_width or h > image_height ->
            {:error, :invalid_size}

          maintain_ratio? ->
            {dividend, divisor} = if w < h, do: {w, image_width}, else: {h, image_height}
            Operation.resize!(image, dividend / divisor)

          true ->
            Operation.resize!(image, w / image_width, vscale: h / image_height)
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp apply_w_h_Transformer(_image, _w_h_parameter, _upscale?, _maintain_ratio?, _settings) do
    {:error, :invalid_size}
  end
end
