defmodule DefaultPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequest,
    InfoRequest
  }

  @impl true
  def info_request(identifier), do: {:ok, %InfoRequest{path: path(identifier)}}

  @impl true
  def data_request(identifier), do: {:ok, %DataRequest{path: path(identifier)}}

  defp path(identifier), do: "test/images/#{identifier}"
end
