defmodule Transformation.Rotation do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def apply(%Image{} = image, "0") do
    # If there is no rotation requested, this function is avoiding any further string parsing.
    image
  end

  def apply(%Image{} = image, rotate_params) when is_binary(rotate_params) do
    mirror_vertically? = String.starts_with?(rotate_params, "!")

    rotate_params
    |> String.replace_leading("!", "")
    |> Float.parse()
    |> case do
      {degrees, ""} when degrees >= 0 and degrees <= 360 ->
        image =
          if mirror_vertically? do
            Operation.flip!(image, :VIPS_DIRECTION_HORIZONTAL)
          else
            image
          end

        Operation.rotate!(image, degrees)

      _ ->
        {:error, :invalid_rotation}
    end
  end

  def apply(error, _), do: error
end
