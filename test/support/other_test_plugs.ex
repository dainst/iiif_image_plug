defmodule ExtraInfoPlug do
  @moduledoc false
  use IIIFImagePlug.V3
  alias IIIFImagePlug.V3.InfoRequestMetadata
  alias IIIFImagePlug.V3.DataRequestMetadata

  @impl true
  def info_metadata(identifier) do
    {
      :ok,
      %InfoRequestMetadata{
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
  def data_metadata(identifier), do: DefaultPlug.data_metadata(identifier)
end

defmodule Custom404Plug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequestMetadata,
    InfoRequestMetadata
  }

  @impl true
  def data_metadata(identifier), do: DefaultPlug.data_metadata(identifier)

  @impl true
  def info_metadata(identifier), do: DefaultPlug.info_metadata(identifier)

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
    DataRequestMetadata,
    InfoRequestMetadata
  }

  @impl true
  def data_metadata(identifier), do: DefaultPlug.data_metadata(identifier)

  @impl true
  def info_metadata(identifier), do: DefaultPlug.info_metadata(identifier)

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
    DataRequestMetadata,
    InfoRequestMetadata
  }

  @impl true
  def info_metadata(identifier) do
    {path, headers} = simulate_additional_identifiers(identifier)

    {
      :ok,
      %InfoRequestMetadata{
        path: path,
        response_headers: headers
      }
    }
  end

  @impl true
  def data_metadata(identifier) do
    {path, headers} =
      simulate_additional_identifiers(identifier)

    {
      :ok,
      %DataRequestMetadata{
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

defmodule CustomRequestErrorPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.RequestError

  @impl true
  def info_metadata("restricted.jpg"), do: unauthorized()

  def info_metadata(identifier), do: DefaultPlug.info_metadata(identifier)

  @impl true
  def data_metadata("restricted.jpg"), do: unauthorized()

  def data_metadata(identifier), do: DefaultPlug.data_metadata(identifier)

  defp unauthorized() do
    {
      :error,
      %RequestError{
        status_code: 401,
        msg: :unauthorized,
        response_headers: [{"something-key", "something value"}]
      }
    }
  end
end

defmodule ContentTypeOverridePlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequestMetadata,
    InfoRequestMetadata
  }

  @impl true
  def info_metadata(identifier), do: DefaultPlug.info_metadata(identifier)

  @impl true
  def data_metadata(identifier) do
    # Test that custom content-type headers are preserved
    case identifier do
      "custom_type.jpg" ->
        {
          :ok,
          %DataRequestMetadata{
            path: "test/images/bentheim_mill.jpg",
            response_headers: [
              {"content-type", "image/custom"},
              {"x-custom-header", "test"}
            ]
          }
        }

      _ ->
        DefaultPlug.data_metadata(identifier)
    end
  end
end

defmodule CachingPlug do
  @moduledoc false
  use IIIFImagePlug.V3

  alias IIIFImagePlug.V3.{
    DataRequestMetadata,
    InfoRequestMetadata
  }

  require Logger

  @impl true
  def info_call(conn) do
    path = construct_cache_path(conn)

    if File.exists?(path) do
      Logger.info("Sending cached file.")
      {:abort, Plug.Conn.send_file(conn, 200, path)}
    else
      Logger.info("Generating JSON file.")
      {:continue, conn}
    end
  end

  @impl true
  def info_metadata(identifier), do: DefaultPlug.info_metadata(identifier)

  @impl true
  def info_response(conn, data) do
    path = construct_cache_path(conn)

    Logger.info("Caching JSON at '#{path}'.")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, Jason.encode!(data))
    conn
  end

  @impl true
  def data_call(conn) do
    path = construct_cache_path(conn)

    if File.exists?(path) do
      Logger.info("Sending cached file.")
      {:abort, Plug.Conn.send_file(conn, 200, path)}
    else
      Logger.info("Continue with processing.")
      {:continue, conn}
    end
  end

  @impl true
  def data_metadata(identifier), do: DefaultPlug.data_metadata(identifier)

  @impl true
  def data_response(%Plug.Conn{} = conn, image, _format) do
    path = construct_cache_path(conn)

    Logger.info("Caching image at '#{path}'.")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    Vix.Vips.Image.write_to_file(image, path)
    conn
  end

  defp construct_cache_path(conn) do
    "./test/tmp/#{Path.join(conn.path_info)}"
  end
end
