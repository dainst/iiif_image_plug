defmodule IIIFImagePlug.V3.DataRequest do
  @moduledoc """
  Used to inject values from your application into the plug when responding to image data requests.

  See also `c:IIIFImagePlug.V3.data_request/1`.

  ## Fields

  - `:path` (required) your local file system path to the image file.
  - `:response_headers` (optional), a list of key-value tuples that should be set as response headers for the request.

  ## Example

      %DataRequest{
        path: "test/images/my_image.jpg",
        response_headers: [
          {"cache-control", "public, max-age=31536000, immutable"}
        ]
      }
  """

  @enforce_keys :path
  defstruct [:path, response_headers: []]

  @type t :: %__MODULE__{
          path: String.t(),
          response_headers: list(tuple())
        }
end
