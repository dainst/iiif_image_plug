defmodule IIIFImagePlug.V3.IdentifierInfo do
  @moduledoc """
  This struct is used for generating an image's `info.json` that is being served by the `IIIFImagePlug.V3` plug.

  ## Fields

  - `:path` (required) your local file system path to the image file.
  - `:rights` (optional) the [rights](https://iiif.io/api/image/3.0/#56-rights) statement for the given image.
  - `:part_of` (optional) the _partOf_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:see_also` (optional) the _seeAlso_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:service` (optional) the _service_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  """

  @enforce_keys :path
  defstruct path: nil, rights: nil, part_of: [], see_also: [], service: []

  @type t :: %__MODULE__{
          path: String.t(),
          rights: String.t() | nil,
          part_of: list(),
          see_also: list(),
          service: list()
        }
end
