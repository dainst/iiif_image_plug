defmodule IIIFImagePlug.V3.Quality do
  @moduledoc false

  alias Vix.Vips.{
    Operation,
    Image
  }

  alias IIIFImagePlug.V3.Settings

  def parse(quality_and_format, %Settings{
        preferred_formats: preferred_formats,
        extra_formats: extra_formats
      })
      when is_binary(quality_and_format) do
    String.split(quality_and_format, ".")
    |> case do
      [quality, format]
      when quality in ["default", "color", "gray", "bitonal"] and
             is_binary(format) ->
        if format in Stream.map(preferred_formats ++ extra_formats, &Atom.to_string/1) do
          %{
            quality: String.to_existing_atom(quality),
            format: format
          }
        end

      _ ->
        :error
    end
  end

  def apply(%Image{} = image, :default, _average) do
    image
  end

  def apply(%Image{} = image, :color, _average) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)
  end

  def apply(%Image{} = image, :gray, _average) do
    Operation.colourspace!(image, :VIPS_INTERPRETATION_B_W)
  end

  def apply(%Image{} = image, :bitonal, average) do
    image
    |> Operation.colourspace!(:VIPS_INTERPRETATION_B_W)
    |> Operation.relational_const!(:VIPS_OPERATION_RELATIONAL_MOREEQ, [average])
  end

  def apply(error, _, _average), do: error
end
