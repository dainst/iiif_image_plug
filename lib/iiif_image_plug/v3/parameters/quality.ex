defmodule IIIFImagePlug.V3.Transformer.Quality do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def parse_and_apply(%Image{} = image, :default) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)
  end

  def parse_and_apply(%Image{} = image, :color) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)
  end

  def parse_and_apply(%Image{} = image, :gray) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_B_W)
  end

  def parse_and_apply(%Image{} = image, :bitonal) do
    image
    |> Operation.colourspace!(:VIPS_INTERPRETATION_B_W)
    |> Operation.relational_const!(:VIPS_OPERATION_RELATIONAL_MOREEQ, [128.0])
  end

  def parse_and_apply(error, _), do: error
end
