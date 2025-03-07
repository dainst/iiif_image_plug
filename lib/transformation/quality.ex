defmodule Transformation.Quality do
  alias Vix.Vips.{
    Operation,
    Image
  }

  def apply(%Image{} = image, :default) do
    image
  end

  def apply(%Image{} = image, :color) do
    # TODO force bw to rgb or something similar?
    image
  end

  def apply(%Image{} = image, :gray) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_B_W)
  end

  def apply(%Image{} = image, :bitonal) do
    image
    |> Operation.colourspace!(:VIPS_INTERPRETATION_B_W)
    |> Operation.relational_const!(:VIPS_OPERATION_RELATIONAL_MOREEQ, [128.0])
  end

  def apply(error, _), do: error
end
