defmodule ExtraInfoPlug do
  @moduledoc false
  use IIIFImagePlug.V3
  alias IIIFImagePlug.V3.InfoRequest
  alias IIIFImagePlug.V3.DataRequest

  @impl true
  def info_request(identifier) do
    {
      :ok,
      %InfoRequest{
        path: "test/images/#{identifier}",
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
        ]
      }
    }
  end

  @impl true
  def data_request(identifier), do: DefaultPlug.data_request(identifier)
end

defmodule Custom404Plug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequest,
    InfoRequest
  }

  @impl true
  def data_request(identifier), do: DefaultPlug.data_request(identifier)

  @impl true
  def info_request(identifier), do: DefaultPlug.info_request(identifier)

  @impl true
  def send_error(%Plug.Conn{} = conn, 404, _error_code) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(
      404,
      "A custom response."
    )
  end
end

defmodule BehindProxyPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequest,
    InfoRequest
  }

  @impl true
  def data_request(identifier), do: DefaultPlug.data_request(identifier)

  @impl true
  def info_request(identifier), do: DefaultPlug.info_request(identifier)

  @impl true
  def scheme(), do: "https"

  @impl true
  def host(), do: "subdomain.example.org"

  @impl true
  def port(), do: 1337
end

defmodule CustomResponseHeaderPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequest,
    InfoRequest
  }

  @impl true
  def info_request(identifier) do
    {path, headers} = simulate_additional_identifiers(identifier)

    {
      :ok,
      %InfoRequest{
        path: path,
        response_headers: headers
      }
    }
  end

  @impl true
  def data_request(identifier) do
    {path, headers} =
      simulate_additional_identifiers(identifier)

    {
      :ok,
      %DataRequest{
        path: path,
        response_headers: headers
      }
    }
  end

  defp simulate_additional_identifiers(identifier) do
    case identifier do
      "private_image.jpg" ->
        {"test/images/bentheim_mill.jpg", [{"cache-control", "private, max-age=3600"}]}

      _ ->
        {"test/images/#{identifier}", [{"cache-control", "public, max-age=31536000, immutable"}]}
    end
  end
end
