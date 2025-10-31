defmodule IIIFImagePlug.MediaTypes do
  @moduledoc false

  @doc """
  Returns the mediatype (MIME) for a given format parameters.
  """
  def get_by_format(format) do
    case String.downcase(format) do
      "jpg" -> "image/jpeg"
      "jpeg" -> "image/jpeg"
      "png" -> "image/png"
      "gif" -> "image/gif"
      "webp" -> "image/webp"
      "svg" -> "image/svg+xml"
      "heif" -> "image/heif"
      "heic" -> "image/heif"
      "tif" -> "image/tiff"
      "tiff" -> "image/tiff"
      "bmp" -> "image/bmp"
      "avif" -> "image/avif"
      _ -> "application/octet-stream"
    end
  end
end
