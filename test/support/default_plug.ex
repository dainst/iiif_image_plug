defmodule DefaultPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequestMetadata,
    InfoRequestMetadata
  }

  @impl true
  def info_metadata(identifier), do: {:ok, %InfoRequestMetadata{path: path(identifier)}}

  @impl true
  def data_metadata(identifier), do: {:ok, %DataRequestMetadata{path: path(identifier)}}

  defp path(identifier), do: "test/images/#{identifier}"
end
