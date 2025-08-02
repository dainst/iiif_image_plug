defmodule IIIFImagePlug.V3.Data.Rotation do
  @moduledoc false
  alias Vix.Vips.{
    Operation,
    Image
  }

  defmodule Rotation do
    @moduledoc false
    @enforce_keys [:degrees]
    defstruct [:degrees, flip?: false]
  end

  def parse(value) when value in ["0", "360"] do
    %Rotation{degrees: 0}
  end

  def parse(value) when value in ["!0", "!360"] do
    %Rotation{degrees: 0, flip?: true}
  end

  def parse(rotate_params) when is_binary(rotate_params) do
    mirror_vertically? = String.starts_with?(rotate_params, "!")

    rotate_params
    |> String.replace_leading("!", "")
    |> Float.parse()
    |> case do
      {degrees, ""} when degrees >= 0 and degrees <= 360 ->
        %Rotation{degrees: degrees, flip?: mirror_vertically?}

      _ ->
        {:error, :invalid_rotation}
    end
  end

  def apply(%Image{} = image, %Rotation{degrees: 0, flip?: false}) do
    image
  end

  def apply(%Image{} = image, %Rotation{degrees: 0, flip?: true}) do
    Operation.flip!(image, :VIPS_DIRECTION_HORIZONTAL)
  end

  def apply(%Image{} = image, %Rotation{degrees: degrees, flip?: flip?}) do
    if Image.has_alpha?(image) do
      image
    else
      # Add alpha channel if missing, so that non-90° rotations have can have a transparent background.
      Operation.bandjoin_const!(image, [255.0])
    end
    |> then(fn image ->
      if flip?, do: Operation.flip!(image, :VIPS_DIRECTION_HORIZONTAL), else: image
    end)
    |> Operation.rotate!(degrees)
  end
end
