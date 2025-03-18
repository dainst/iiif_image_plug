defmodule IIIFImagePlug.V3.Quality do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def parse_and_apply(%Image{} = image, :default, _average) do
    image
  end

  def parse_and_apply(%Image{} = image, :color, _average) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)
  end

  def parse_and_apply(%Image{} = image, :gray, _average) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_B_W)
  end

  def parse_and_apply(%Image{} = image, :bitonal, average) do
    image
    |> Operation.colourspace!(:VIPS_INTERPRETATION_B_W)
    |> Operation.relational_const!(:VIPS_OPERATION_RELATIONAL_MOREEQ, [average])
  end

  def parse_and_apply(error, _, _average), do: error
end
