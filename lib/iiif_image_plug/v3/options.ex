defmodule IIIFImagePlug.V3.Options do
  @moduledoc """
  Defines the IIIFImagePlug.V3 plug options.

  The plug relies on [Vix](https://hex.pm/packages/vix) package for the image processing, which includes a
  precompiled libvips binary out of the box (Linux/MacOS). The possible values for `:preferred_formats` and
  `extra_formats` thus are currently as follows: `[:jpg, :png, :webp, :tif, :gif, :raw, :vips]`.

  You can configure Vix to use your own installation of libvips if you need other formats, see the
  [Vix documentation](https://hexdocs.pm/vix/readme.html#content).

  ## Options

  ### `:max_width` (default: `10000`)
  The maximum image width the plug will serve.

  ### `:max_height` (default: `10000`)
  The maximum image height the plug will serve.

  ### `:max_area` (default: `100000000`)
  The maximum amount of image pixels the plug will serve (does not necessarily have to be `max_width` * `max_height`).

  ### `:preferred_formats` (default: `[:jpg]`)
  The [preferred formats](https://iiif.io/api/image/3.0/#55-preferred-formats) to be used for your service.

  ### `:extra_formats` (default: `[:webp, :png]`)
  The [extra formats](https://iiif.io/api/image/3.0/#57-extra-functionality) your service can deliver.

  ### `:temp_dir` (default: `uses System.tmp_dir!/0`)

  To be more precise, the default evaluates [System.tmp_dir!/0](https://hexdocs.pm/elixir/System.html#tmp_dir!/0) and creates
  a directory "iiif_image_plug" there.

  Because of how the TIF file format is structured, the plug can not stream the image if tif was _requested_ as the response
  [format](https://iiif.io/api/image/3.0/#45-format). Instead, the image gets first written to a temporary file, which is then streamed
  from disk and getting deleted afterwards.

  If you want to forgo this file creation, you can set this option to `:buffer` instead of a file path. This will configure
  the plug to write the complete image to memory instead of disk - which is faster but also may cause memory issues if
  very large images are requested.
  """

  defstruct max_width: 10000,
            max_height: 10000,
            max_area: 10000 * 10000,
            preferred_formats: [:jpg],
            extra_formats: [:webp, :png],
            temp_dir: Path.join(System.tmp_dir!(), "iiif_image_plug")

  @type t :: %__MODULE__{
          max_width: integer(),
          max_height: integer(),
          max_area: integer(),
          preferred_formats: list(),
          extra_formats: list(),
          temp_dir: String.t() | atom()
        }
end
