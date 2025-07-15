defmodule DefaultPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  @impl true
  def identifier_to_path(identifier) do
    {:ok, "test/images/#{identifier}"}
  end

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

  @impl true
  def identifier_to_path(identifier) do
    {:ok, "test/images/#{identifier}"}
  end

  @impl true
  def host() do
    "localhost"
  end

  @impl true
  def port() do
    4000
  end

  @impl true
  def rights(_identifier) do
    "https://creativecommons.org/publicdomain/zero/1.0/"
  end

  @impl true
  def see_also(_identifier) do
    [
      %{
        id: "https://example.org/image1.xml",
        label: %{en: ["Technical image metadata"]},
        type: "Dataset",
        format: "text/xml",
        profile: "https://example.org/profiles/imagedata"
      }
    ]
  end

  @impl true
  def part_of(_identifier) do
    [
      %{
        id: "https://example.org/manifest/1",
        type: "Manifest",
        label: %{en: ["A Book"]}
      }
    ]
  end

  @impl true
  def service(_identifier) do
    [
      %{
        "@id": "https://example.org/auth/login",
        "@type": "AuthCookieService1",
        profile: "http://iiif.io/api/auth/1/login",
        label: "Login to Example Institution"
      }
    ]
  end
end

defmodule Custom404Plug do
  @moduledoc false
  use IIIFImagePlug.V3

  @impl true
  def identifier_to_path(identifier) do
    {:ok, "test/images/#{identifier}"}
  end

  @impl true
  def host() do
    "localhost"
  end

  @impl true
  def port() do
    4000
  end

  @impl true
  def send_error(%Plug.Conn{} = conn, 404, _error_code, _error_msg) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(
      404,
      "A custom response."
    )
  end
end
