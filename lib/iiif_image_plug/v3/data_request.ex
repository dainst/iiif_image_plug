defmodule IIIFImagePlug.V3.DataRequest do
  @enforce_keys :path
  defstruct [:path, response_headers: []]
end
