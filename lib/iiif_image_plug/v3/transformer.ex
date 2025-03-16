defmodule IIIFImagePlug.V3.Transformer do
  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.Opts

  alias IIIFImagePlug.V3.Transformer.{
    Quality,
    Region,
    Rotation,
    Size
  }

  def start(
        %Image{} = input_file,
        region,
        size,
        rotation,
        quality,
        %Opts{} = opts
      ) do
    input_file
    |> Region.parse_and_apply(URI.decode(region))
    |> Size.parse_and_apply(URI.decode(size), opts)
    |> Rotation.parse_and_apply(rotation)
    |> Quality.parse_and_apply(quality)
  end
end
