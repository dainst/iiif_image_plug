defmodule IIIFImagePlug.V3.InfoRequestMetadata do
  @moduledoc """
  A struct used to inject values from your application into the plug when responding to information request (info.json).

  See also `c:IIIFImagePlug.V3.info_metadata/1`.

  ## Fields

  - `:path` (required) your local file system path to the image file.
  - `:rights` (optional) the [rights](https://iiif.io/api/image/3.0/#56-rights) statement for the given image.
  - `:part_of` (optional) the _partOf_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:see_also` (optional) the _seeAlso_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:service` (optional) the _service_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:response_headers` (optional), a list of key-value tuples that should be set as response headers for the request.

  ## Example

      %InfoRequestMetadata{
        path: "test/images/my_image.jpg",
        rights: "https://creativecommons.org/publicdomain/zero/1.0/",
        see_also: [
          %{
            id: "https://example.org/image1.xml",
            label: %{en: ["Technical image metadata"]},
            type: "Dataset",
            format: "text/xml",
            profile: "https://example.org/profiles/imagedata"
          }
        ],
        part_of: [
          %{
            id: "https://example.org/manifest/1",
            type: "Manifest",
            label: %{en: ["A Book"]}
          }
        ],
        service: [
          %{
            "@id": "https://example.org/auth/login",
            "@type": "AuthCookieService1",
            profile: "http://iiif.io/api/auth/1/login",
            label: "Login to Example Institution"
          }
        ],
        response_headers: [
          {"cache-control", "public, max-age=31536000, immutable"}
        ]
      }
  """

  @enforce_keys :path
  defstruct [:path, :rights, part_of: [], see_also: [], service: [], response_headers: []]

  @type t :: %__MODULE__{
          path: String.t(),
          rights: String.t() | nil,
          part_of: list(),
          see_also: list(),
          service: list(),
          response_headers: list(tuple())
        }
end
