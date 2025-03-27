defmodule IIIFImagePlug.V3.Rotation do
  alias Vix.Vips.{
    Operation,
    Image
  }

  defmodule Rotation do
    @enforce_keys [:degrees]
    defstruct [:degrees, flip?: false]
  end

  def parse("0") do
    %Rotation{degrees: 0}
  end

  def parse("!0") do
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

  def parse(_param) do
    {:error, :invalid_rotation}
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
      Operation.bandjoin_const!(image, [255.0])
    end
    |> then(fn image ->
      if flip?, do: Operation.flip!(image, :VIPS_DIRECTION_HORIZONTAL), else: image
    end)
    |> Operation.rotate!(degrees)
  end

  def apply(error, _rotation) do
    error
  end
end
