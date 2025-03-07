defmodule Transformation.Size do
  alias Vix.Vips.{
    Operation,
    Image
  }

  alias IIIFPlug.V3.Opts

  def apply(%Image{} = image, "max", %Opts{} = plug_opts) do
    image_width = Image.width(image)
    image_height = Image.height(image)

    image_area = image_width * image_height

    factor =
      cond do
        image_area > plug_opts.max_area ->
          factor = :math.sqrt(plug_opts.max_area / image_area)

          width_with_factor = image_width * factor
          height_with_factor = image_height * factor

          with {:width_ok, true} <- {:width_ok, width_with_factor < plug_opts.max_width},
               {:height_ok, true} <- {:height_ok, height_with_factor < plug_opts.max_height} do
            factor
          else
            {:height_ok, false} ->
              plug_opts.max_height / image_height

            {:width_ok, false} ->
              factor = plug_opts.max_width / image_width

              height_with_factor = image_height * factor

              if height_with_factor > plug_opts.max_height do
                plug_opts.max_height / image_height
              else
                factor
              end
          end

        image_width > plug_opts.max_width ->
          factor = plug_opts.max_width / image_width

          height_with_factor = image_height * factor

          if height_with_factor > plug_opts.max_height do
            plug_opts.max_height / image_height
          else
            factor
          end

        image_height > plug_opts.max_height ->
          plug_opts.max_height / image_height

        true ->
          1.0
      end

    Operation.resize!(image, factor, vscale: factor)
  end

  def apply(%Image{} = image, "^max", plug_opts) do
    # TODO: This is still incomplete and turning into spaghetti.
    # - should probably a recursive `fit_factor_for_opts` function
    # - rounding errors resize! seems to round up pixel values sometimes,
    #   what might cause the area a side to exceed the plug's limit even
    #   though the factor passed was correct.
    image_width = Image.width(image)
    image_height = Image.height(image)

    image_area = image_width * image_height

    factor =
      cond do
        image_area < plug_opts.max_area ->
          factor = :math.sqrt(plug_opts.max_area / image_area)

          width_with_factor = image_width * factor
          height_with_factor = image_height * factor

          with {:width_ok, true} <- {:width_ok, width_with_factor < plug_opts.max_width},
               {:height_ok, true} <- {:height_ok, height_with_factor < plug_opts.max_height} do
            factor
          else
            {:height_ok, false} ->
              factor = plug_opts.max_height / image_height

              width_with_factor = image_width * factor

              if width_with_factor > plug_opts.max_width do
                plug_opts.max_width / image_width
              else
                factor
              end

            {:width_ok, false} ->
              factor = plug_opts.max_width / image_width

              height_with_factor = image_height * factor

              if height_with_factor > plug_opts.max_height do
                plug_opts.max_height / image_height
              else
                factor
              end
          end

        image_width < plug_opts.max_width ->
          factor = plug_opts.max_width / image_width

          height_with_factor = image_height * factor

          if height_with_factor > plug_opts.max_height do
            plug_opts.max_height / image_height
          else
            factor
          end

        image_height < plug_opts.max_height ->
          factor = plug_opts.max_height / image_height

          width_with_factor = image_width * factor

          if width_with_factor > plug_opts.max_width do
            plug_opts.max_width / image_width
          else
            factor
          end

        true ->
          1.0
      end

    Operation.resize!(image, factor)
  end

  def apply(%Image{} = image, size_parameter, _plug_opts) when is_binary(size_parameter) do
    upscale? = String.starts_with?(size_parameter, "^")
    size_parameter = String.replace_leading(size_parameter, "^", "")

    maintain_ratio? = String.starts_with?(size_parameter, "!")
    size_parameter = String.replace_leading(size_parameter, "!", "")

    if String.starts_with?(size_parameter, "pct:") do
      size_parameter
      |> String.replace_leading("pct:", "")
      |> Integer.parse()
      |> case do
        {percent, ""} when percent >= 0 and percent > 100 and upscale? ->
          # TODO: fit factor to plug_opts
          Operation.resize!(image, percent / 100)

        {percent, ""} when percent >= 0 and percent > 100 ->
          {:error, :invalid_size}

        {percent, ""} when percent >= 0 ->
          Operation.resize!(image, percent / 100)

        _ ->
          {:error, :invalid_size}
      end
    else
      w_h = String.split(size_parameter, ",")

      apply_w_h_parameters(image, w_h, upscale?, maintain_ratio?)
    end
  end

  def apply(error, _, _), do: error

  defp apply_w_h_parameters(image, [w_parameter, ""], upscale?, _maintain_ratio?) do
    Integer.parse(w_parameter)
    |> case do
      {w, ""} ->
        image_width = Image.width(image)

        cond do
          upscale? ->
            # TODO: fit factor to plug_opts
            Operation.resize!(image, w / image_width)

          w > image_width ->
            {:error, :invalid_size}

          true ->
            Operation.resize!(image, w / image_width)
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp apply_w_h_parameters(image, ["", h_parameter], upscale?, _maintain_ratio?) do
    Integer.parse(h_parameter)
    |> case do
      {h, ""} ->
        image_height = Image.height(image)

        cond do
          upscale? ->
            # TODO: fit factor to plug_opts
            Operation.resize!(image, h / image_height)

          h > image_height ->
            {:error, :invalid_size}

          true ->
            Operation.resize!(image, h / image_height)
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp apply_w_h_parameters(image, [w_parameter, h_parameter], upscale?, maintain_ratio?) do
    {Integer.parse(w_parameter), Integer.parse(h_parameter)}
    |> case do
      {{w, ""}, {h, ""}} ->
        image_width = Image.width(image)
        image_height = Image.height(image)

        cond do
          upscale? and maintain_ratio? ->
            # TODO: fit factor to plug_opts
            {dividend, divisor} = if w > h, do: {w, image_width}, else: {h, image_height}
            Operation.resize!(image, dividend / divisor)

          upscale? ->
            cond do
              w > h ->
                Operation.resize!(image, w / image_width, vscale: 1.0)

              w < h ->
                Operation.resize!(image, 1.0, vscale: h / image_height)

              true ->
                # TODO: fit factor to plug_opts
                Operation.resize!(image, w / image_width, vscale: h / image_height)
            end

          w > image_width or h > image_height ->
            {:error, :invalid_size}

          maintain_ratio? ->
            {dividend, divisor} = if w > h, do: {w, image_width}, else: {h, image_height}
            Operation.resize!(image, dividend / divisor)

          true ->
            Operation.resize!(image, w / image_width, vscale: h / image_height)
        end

      _ ->
        {:error, :invalid_size}
    end
  end

  defp apply_w_h_parameters(_, _, _, _) do
    {:error, :invalid_size}
  end
end
