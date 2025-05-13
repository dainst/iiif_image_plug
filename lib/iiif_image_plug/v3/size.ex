defmodule IIIFImagePlug.V3.Size do
  @moduledoc false
  alias Vix.Vips.Operation
  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.Settings

  defmodule Scaling do
    @moduledoc false
    @enforce_keys [:scale]
    defstruct [:scale, :vscale]
  end

  def parse(%Image{} = image, "max", %Settings{} = settings) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    image_area = image_width * image_height

    # Select the smallest factor that would scale the image to one of the plug's maxima.
    # We filter only for values < 1.
    # - If it is larger than 1, the image would get scaled up by the factor, we do not want that here (that would be "^max").
    # - If it is smaller than 1, the image will get scaled down.
    # - If all factors are larger than 1, all dimensions and the area fall within the plugs maxima and we fallback to a factor of 1 (no scaling).

    scale =
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

    %Scaling{scale: scale}
  end

  def parse(%Image{} = image, "^max", %Settings{} = settings) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    image_area = image_width * image_height

    # Select the smallest factor that would scale the image to one of the plug's maxima.

    scale =
      Enum.min([
        :math.sqrt(settings.max_area / image_area),
        settings.max_width / image_width,
        settings.max_height / image_height
      ])

    %Scaling{scale: scale}
  end

  def parse(%Image{} = image, size_parameter, %Settings{} = settings)
      when is_binary(size_parameter) do
    upscale? = String.starts_with?(size_parameter, "^")
    size_parameter = String.replace_leading(size_parameter, "^", "")

    maintain_ratio? = String.starts_with?(size_parameter, "!")
    size_parameter = String.replace_leading(size_parameter, "!", "")

    if String.starts_with?(size_parameter, "pct:") do
      parse_percent(image, size_parameter, upscale?, settings)
    else
      w_h = String.split(size_parameter, ",")
      parse_w_h(image, w_h, upscale?, maintain_ratio?, settings)
    end
  end

  def apply(%Image{} = image, %Scaling{scale: 1, vscale: nil}) do
    image
  end

  def apply(%Image{} = image, %Scaling{scale: scale, vscale: nil}) do
    Operation.resize!(image, scale)
  end

  def apply(%Image{} = image, %Scaling{scale: scale, vscale: vscale}) do
    Operation.resize!(image, scale, vscale: vscale)
  end

  defp parse_percent(%Image{} = image, parameter, upscale?, %Settings{} = settings) do
    parameter
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

        scale =
          if requested_factor < valid_maximum_factor,
            do: requested_factor,
            else: valid_maximum_factor

        %Scaling{scale: scale}

      {percent, ""} when percent > 100 ->
        {:error, :invalid_size}

      {percent, ""} when percent >= 0 ->
        %Scaling{scale: percent / 100}

      _ ->
        {:error, :invalid_size}
    end
  end

  defp parse_w_h(
         %Image{} = image,
         [w_parameter, ""],
         upscale?,
         _maintain_ration?,
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

            scale =
              if requested_factor < valid_maximum_factor,
                do: requested_factor,
                else: valid_maximum_factor

            %Scaling{scale: scale}

          w > image_width ->
            {:error, :invalid_size}

          true ->
            %Scaling{scale: w / image_width}
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp parse_w_h(
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

            %Scaling{scale: factor}

          h > image_height ->
            {:error, :invalid_size}

          true ->
            %Scaling{scale: h / image_height}
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp parse_w_h(
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

            %Scaling{scale: factor}

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

            %Scaling{scale: width_factor, vscale: height_factor}

          w > image_width or h > image_height ->
            {:error, :invalid_size}

          maintain_ratio? ->
            {dividend, divisor} = if w < h, do: {w, image_width}, else: {h, image_height}
            %Scaling{scale: dividend / divisor}

          true ->
            %Scaling{scale: w / image_width, vscale: h / image_height}
        end

      _ ->
        {:error, :invalid_size}
    end
  end
end
