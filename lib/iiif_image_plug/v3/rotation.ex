defmodule IIIFImagePlug.V3.Rotation do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def parse_and_apply(%Image{} = image, "0") do
    # If there is no rotation requested, this function is avoiding any further string parsing.
    image
  end

  def parse_and_apply(%Image{} = image, rotate_params) when is_binary(rotate_params) do
    image =
      if Image.has_alpha?(image) do
        image
      else
        Operation.bandjoin_const!(image, [255.0])
      end

    mirror_vertically? = String.starts_with?(rotate_params, "!")

    rotate_params
    |> String.replace_leading("!", "")
    |> Float.parse()
    |> case do
      {degrees, ""} when degrees >= 0 and degrees <= 360 ->
        if mirror_vertically? do
          Operation.flip!(image, :VIPS_DIRECTION_HORIZONTAL)
        else
          image
        end
        |> Operation.rotate!(degrees)

      _ ->
        {:error, :invalid_rotation}
    end
  end

  def parse_and_apply(error, _), do: error
end
