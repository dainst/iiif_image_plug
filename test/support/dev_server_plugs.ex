defmodule DefaultPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    Data,
    Information
  }

  @impl true
  def identifier_info(identifier) do
    {
      :ok,
      %Information{
        path: "test/images/#{identifier}"
      }
    }
  end

  @impl true
  def identifier_path(identifier), do: {:ok, %Data{path: "test/images/#{identifier}"}}

  @impl true
  def host() do
    "localhost"
  end

  @impl true
  def port() do
    4000
  end
end

defmodule ExtraInfoPlug do
  @moduledoc false
  use IIIFImagePlug.V3
  alias IIIFImagePlug.V3.Information
  alias IIIFImagePlug.V3.Data

  @impl true
  def identifier_info(identifier) do
    {
      :ok,
      %Information{
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
  def identifier_path(identifier), do: {:ok, %Data{path: "test/images/#{identifier}"}}

  @impl true
  def host() do
    "localhost"
  end

  @impl true
  def port() do
    4000
  end
end

defmodule Custom404Plug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    Data,
    Information
  }

  @impl true
  def identifier_info(identifier) do
    {
      :ok,
      %Information{
        path: "test/images/#{identifier}"
      }
    }
  end

  @impl true
  def identifier_path(identifier), do: {:ok, %Data{path: "test/images/#{identifier}"}}

  @impl true
  def host() do
    "localhost"
  end

  @impl true
  def port() do
    4000
  end

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

defmodule CustomResponseHeaderPlug do
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    Data,
    Information
  }

  @impl true
  def identifier_info(identifier) do
    {path, headers} = simulate_additional_identifiers(identifier)

    {
      :ok,
      %Information{
        path: path,
        response_headers: headers
      }
    }
  end

  @impl true
  def identifier_path(identifier) do
    {path, headers} =
      simulate_additional_identifiers(identifier)

    {
      :ok,
      %Data{
        path: path,
        response_headers: headers
      }
    }
  end

  @impl true
  def host(), do: "localhost"

  @impl true
  def port(), do: 4001

  defp simulate_additional_identifiers(identifier) do
    case identifier do
      "private_image.jpg" ->
        {"test/images/bentheim_mill.jpg", [{"cache-control", "private, max-age=3600"}]}

      _ ->
        {"test/images/#{identifier}", [{"cache-control", "public, max-age=31536000, immutable"}]}
    end
  end
end
