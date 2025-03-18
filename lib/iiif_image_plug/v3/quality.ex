defmodule IIIFImagePlug.V3.Quality do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def parse_and_apply(%Image{} = image, :default) do
    image
  end

  def parse_and_apply(%Image{} = image, :color) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)
  end

  def parse_and_apply(%Image{} = image, :gray) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_B_W)
  end

  def parse_and_apply(%Image{} = image, :bitonal) do
    avg = Operation.avg!(image)

    image
    |> Operation.colourspace!(:VIPS_INTERPRETATION_B_W)
    |> Operation.relational_const!(:VIPS_OPERATION_RELATIONAL_MOREEQ, [avg])
  end

  def parse_and_apply(error, _), do: error
end
