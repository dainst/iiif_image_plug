defmodule IIIFImagePlug.V3.RequestError do
  @moduledoc """
  Used to inject an error code, message and response headers from your application into the plug
  when a `c:IIIFImagePlug.V3.info_request/1` or `c:IIIFImagePlug.V3.data_request/1` is invalid (for
  example if the identifier does not match anything, 404, or the image is currently access restricted
  401 or 403).

  ## Fields

  - `:status_code` (required) a HTTP status code.
  - `:msg` (optional) an optional message, by default the plug will put that message in the response's json body. This can also be used
  to be picked up by a custom `c:IIIFImagePlug.V3.send_error/3` implementation later on.
  - `:response_headers` (optional) a list of key-value tuples that should be set as response headers for the error response.

  ## Example:

      %RequestError{
        code: 401,
        msg: :unauthorized,
        response_headers: [{"something-key", "something value"}]
      }
  """

  @enforce_keys :status_code
  defstruct [:status_code, :msg, response_headers: []]

  @type t :: %__MODULE__{
          status_code: pos_integer(),
          msg: atom() | String.t(),
          response_headers: list(tuple())
        }
end
