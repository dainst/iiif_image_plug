defmodule IIIFImagePlug.V3Test do
  use ExUnit.Case, async: true
  doctest IIIFImagePlug.V3

  import Plug.Test
  import ExUnit.CaptureLog

  @opts DevServerRouter.init([])

  @sample_jpg_name "bentheim_mill.jpg"
  @sample_pyramid_tif_name "bentheim_mill_pyramid.tif"
  @sample_png_for_validator "official_test_image.png"

  @expected_files_root "test/images/expected_results"

  @expected_file_info %{
    "@context" => "http://iiif.io/api/image/3/context.json",
    "extraFormats" => ["webp", "png", "tif"],
    "extraQualities" => ["color", "gray", "bitonal"],
    "extra_features" => [
      "mirroring",
      "regionByPct",
      "regionByPx",
      "regionSquare",
      "rotationArbitrary",
      "sizeByConfinedWh",
      "sizeByH",
      "sizeByPct",
      "sizeByW",
      "sizeByWh",
      "sizeUpscaling"
    ],
    "height" => 300,
    # in the Elixir test environment, the default %Conn{} value for `:host` is "www.example.com" and for `:port` is 80.
    "id" => "http://www.example.com:80/bentheim_mill.jpg",
    "maxArea" => 240_000,
    "maxHeight" => 400,
    "maxWidth" => 600,
    "preferredFormat" => ["jpg"],
    "profile" => "level2",
    "protocol" => "http://iiif.io/api/image",
    "type" => "ImageService3",
    "width" => 500
  }

  test "returns the info.json for the sample image image" do
    conn = conn(:get, "/#{@sample_jpg_name}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert @expected_file_info = response
  end

  test "returns the correct info.json on non-root paths for the sample image image" do
    conn = conn(:get, "/some/nested/route/#{@sample_jpg_name}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert %{
             "id" => "http://www.example.com:80/some/nested/route/bentheim_mill.jpg"
           } = response
  end

  test "returns the info.json for the sample image image tif" do
    conn = conn(:get, "/#{@sample_pyramid_tif_name}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert %{
             "id" => "http://www.example.com:80/bentheim_mill_pyramid.tif",
             "sizes" => [%{"height" => 150, "type" => "Size", "width" => 250}]
           } = response
  end

  test "returns additional linking properties and rights info if defined" do
    extended =
      @expected_file_info
      |> Map.merge(%{
        "rights" => "https://creativecommons.org/publicdomain/zero/1.0/",
        "partOf" => [
          %{
            "id" => "https://example.org/manifest/1",
            "label" => %{"en" => ["A Book"]},
            "type" => "Manifest"
          }
        ],
        "seeAlso" => [
          %{
            "format" => "text/xml",
            "id" => "https://example.org/image1.xml",
            "label" => %{"en" => ["Technical image metadata"]},
            "profile" => "https://example.org/profiles/imagedata",
            "type" => "Dataset"
          }
        ],
        "service" => [
          %{
            "@id" => "https://example.org/auth/login",
            "@type" => "AuthCookieService1",
            "label" => "Login to Example Institution",
            "profile" => "http://iiif.io/api/auth/1/login"
          }
        ],
        "maxArea" => 100_000_000,
        "maxHeight" => 10000,
        "maxWidth" => 10000,
        "extraFormats" => ["webp", "png"]
      })

    conn = conn(:get, "/#{@sample_jpg_name}/info.json")
    conn = DevServerRouter.call(conn, @opts)

    response_default = Jason.decode!(conn.resp_body)

    extended =
      Map.replace(extended, "id", "http://www.example.com:80/extra_info/bentheim_mill.jpg")

    conn = conn(:get, "/extra_info/#{@sample_jpg_name}/info.json")
    conn = DevServerRouter.call(conn, @opts)
    response_extra = Jason.decode!(conn.resp_body)

    refute extended == response_default
    assert extended == response_extra
  end

  test "redirects to info.json if only identifier is provided" do
    conn = conn(:get, "/#{@sample_pyramid_tif_name}")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :set
    assert conn.status == 302

    assert ["http://www.example.com:80/bentheim_mill_pyramid.tif/info.json"] =
             Plug.Conn.get_resp_header(conn, "location")
  end

  test "sends 404 for unknown paths" do
    conn = conn(:get, "/this/wont/do")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404

    response = Jason.decode!(conn.resp_body)

    assert %{"error" => "unknown_route"} = response
  end

  test "returns 404 for unknown identifier" do
    unknown_identifier = "nope.jpg"

    conn = conn(:get, "/#{unknown_identifier}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404

    response = Jason.decode!(conn.resp_body)

    assert %{"error" => "no_file"} = response
  end

  test "returns 500 when attempting to open unsupported file and error gets logged" do
    unsupported = "not_an_image.txt"

    conn = conn(:get, "/#{unsupported}/info.json")

    log =
      capture_log(fn ->
        conn = DevServerRouter.call(conn, @opts)
        assert conn.state == :sent
        assert conn.status == 500
      end)

    assert log =~ "File matching identifier '#{unsupported}' could not be opened as an image."
  end

  test "uses error status callbacks provided" do
    unknown_identifier = "nope.jpg"

    conn = conn(:get, "/custom_404_route/#{unknown_identifier}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404

    assert "A custom response." = conn.resp_body
  end

  test "uses error status callbacks fallback if custom ones do not match" do
    # invalid region parameter should cause 400, which is not customized.
    conn = conn(:get, "/#{@sample_jpg_name}/nope/max/0/default.jpg")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 400

    assert "{\"error\":\"invalid_region\"}" = conn.resp_body
  end

  describe "image data endpoint" do
    test "returns the expected image data for the different test images" do
      get_expected_file_paths()
      |> Task.async_stream(fn {file_name, path} ->
        conn = conn(:get, "/#{file_name}/#{path}" |> URI.encode())

        conn = DevServerRouter.call(conn, @opts)

        if String.ends_with?(path, "tif") do
          assert conn.state == :file
        else
          assert conn.state == :chunked
        end

        assert conn.status == 200

        {:ok, from_file} =
          Image.open("#{@expected_files_root}/#{file_name}/#{path}")

        {:ok, from_response} = Image.from_binary(conn.resp_body)

        assert {:ok, +0.0, _image} = Image.compare(from_file, from_response)
      end)
      |> Enum.to_list()
    end

    test "returns the correct image data of the rectangle provided by the official validator" do
      conn = conn(:get, "/#{@sample_png_for_validator}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :chunked
      assert conn.status == 200
    end

    test "returns 404 for unknown identifier" do
      unknown_identifier = "does_not_exist.jpg"
      conn = conn(:get, "/#{unknown_identifier}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 404

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "no_file"} = response
    end

    test "returns 400 for invalid region parameter" do
      conn = conn(:get, "/#{@sample_jpg_name}/nope/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 400 for invalid percentage region parameter" do
      conn = conn(:get, "/#{@sample_jpg_name}/pct:nope/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 400 for invalid w,h size parameters" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/no,pe/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400

      conn = conn(:get, "/#{@sample_jpg_name}/full/,pe/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400

      conn = conn(:get, "/#{@sample_jpg_name}/full/no,/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400

      conn = conn(:get, "/#{@sample_jpg_name}/full/nope/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 400 for invalid percent size parameter" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/pct:nope/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 400 if percent size parameter is larger then 100 without requesting upscaling" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/pct:120/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 400 for invalid rotation parameter" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/nope/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 400 for invalid quality parameter" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/nope/default_jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 400
    end

    test "returns 500 when attempting to open unsupported file and error gets logged" do
      unsupported = "not_an_image.txt"

      conn = conn(:get, "/#{unsupported}/full/max/0/default.jpg")

      log =
        capture_log(fn ->
          conn = DevServerRouter.call(conn, @opts)
          assert conn.state == :sent
          assert conn.status == 500
        end)

      assert log =~ "File matching identifier '#{unsupported}' could not be opened as an image."
    end

    test "returns 400 for wellformed but unsupported quality or format" do
      conn = conn(:get, "/no_extra_formats/#{@sample_jpg_name}/full/max/0/default.png")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response

      conn = conn(:get, "/no_extra_formats/#{@sample_jpg_name}/full/max/0/default.tif")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response

      conn = conn(:get, "/no_extra_formats/#{@sample_jpg_name}/full/max/0/default.webp")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response

      conn = conn(:get, "/no_extra_formats/#{@sample_jpg_name}/full/max/0/default.txt")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response

      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/rainbow.jpg")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response
    end

    test "returns buffered tiff files" do
      path = "#{@sample_jpg_name}/full/max/0/default.tif"

      conn = conn(:get, "/buffered_tiffs/#{path}")

      conn = DevServerRouter.call(conn, @opts)

      refute conn.state == :file
      assert conn.state == :sent
      assert conn.status == 200

      {:ok, from_file} =
        Image.open("#{@expected_files_root}/#{path}")

      {:ok, from_response} = Image.from_binary(conn.resp_body)

      assert {:ok, +0.0, _image} = Image.compare(from_file, from_response)
    end

    test "sets response headers for image info when configured" do
      conn = conn(:get, "/custom_response_headers/#{@sample_jpg_name}/info.json")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      assert Plug.Conn.get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      conn = conn(:get, "/custom_response_headers/private_image.jpg/info.json")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, max-age=3600"]
    end

    test "sets response headers for image data when configured" do
      conn = conn(:get, "/custom_response_headers/#{@sample_jpg_name}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      assert Plug.Conn.get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      conn = conn(:get, "/custom_response_headers/private_image.jpg/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, max-age=3600"]
    end

    test "does not set response headers for redirects" do
      conn = conn(:get, "/custom_response_headers/#{@sample_jpg_name}")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :set]
      assert conn.status == 302
      # Redirects should not have our custom cache headers
      cache_control_headers = Plug.Conn.get_resp_header(conn, "cache-control")
      refute "public, max-age=31536000, immutable" in cache_control_headers
    end

    test "does not set response headers for errors" do
      conn = conn(:get, "/custom_response_header/nonexistent.jpg/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 404

      # The test plug seems to set default headers, we just care that our custom headers aren't set
      cache_control_headers = Plug.Conn.get_resp_header(conn, "cache-control")
      refute "public, max-age=31536000, immutable" in cache_control_headers
    end

    test "sets correct content-type based on actual image format for JPEG" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/jpeg")
    end

    test "sets correct content-type based on actual image format for PNG" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.png")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/png")
    end

    test "sets correct content-type based on actual image format for WebP" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.webp")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/webp")
    end

    test "sets correct content-type based on actual image format for TIFF" do
      conn = conn(:get, "/#{@sample_pyramid_tif_name}/full/max/0/default.tif")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :file]
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/tiff")
    end

    test "response headers from DataRequest are applied along with correct content-type" do
      conn = conn(:get, "/custom_response_headers/#{@sample_jpg_name}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      # Custom headers should be applied
      assert Plug.Conn.get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      # Content-type should be auto-detected
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/jpeg")
    end

    test "custom content-type in response headers is preserved" do
      # Test that custom content-type headers in DataRequest are preserved
      conn = conn(:get, "/content_type_override/custom_type.jpg/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      # Custom content-type should be preserved
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["image/custom"]

      # Other custom headers should also be applied
      assert Plug.Conn.get_resp_header(conn, "x-custom-header") == ["test"]
    end

    test "content-type detection works for all send methods" do
      # Test buffered send (TIFF with buffer option)
      conn = conn(:get, "/buffered_tiffs/#{@sample_jpg_name}/full/max/0/default.tif")
      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/tiff")

      # Test stream send (JPEG)
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.jpg")
      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :chunked
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/jpeg")

      # Test file send (regular TIFF)
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.tif")
      conn = DevServerRouter.call(conn, @opts)
      assert conn.state in [:sent, :file]
      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/tiff")
    end

    test "scheme, host and port get overridden by callback" do
      conn = conn(:get, "/proxy_setup/#{@sample_jpg_name}/info.json")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      expected_id = "https://subdomain.example.org:1337/proxy_setup/#{@sample_jpg_name}"

      %{"id" => ^expected_id} = Jason.decode!(conn.resp_body)
    end

    test "request errors defined in callbacks are returned correctly" do
      # Information request for restricted identifier should get blocked.
      conn = conn(:get, "/restricted_access/restricted.jpg/info.json")
      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 401

      assert %{"error" => "unauthorized"} = Jason.decode!(conn.resp_body)
      assert ["something value"] = Plug.Conn.get_resp_header(conn, "something-key")

      # Information request for sample image should still work.
      conn = conn(:get, "/restricted_access/#{@sample_jpg_name}/info.json")
      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200

      # Data request for restricted identifier should get blocked.
      conn = conn(:get, "/restricted_access/restricted.jpg/full/max/0/default.jpg")
      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 401

      assert %{"error" => "unauthorized"} = Jason.decode!(conn.resp_body)
      assert ["something value"] = Plug.Conn.get_resp_header(conn, "something-key")

      # Data request for sample image should still work.
      conn = conn(:get, "/restricted_access/#{@sample_jpg_name}/full/max/0/default.jpg")
      conn = DevServerRouter.call(conn, @opts)

      assert conn.state in [:sent, :chunked]
      assert conn.status == 200
    end
  end

  defp get_expected_file_paths() do
    File.ls!(@expected_files_root)
    |> Enum.map(fn file_name ->
      File.ls!("#{@expected_files_root}/#{file_name}")
      |> Enum.map(fn region ->
        File.ls!("#{@expected_files_root}/#{file_name}/#{region}")
        |> Enum.map(fn size ->
          File.ls!("#{@expected_files_root}/#{file_name}/#{region}/#{size}")
          |> Enum.map(fn rotation ->
            File.ls!("#{@expected_files_root}/#{file_name}/#{region}/#{size}/#{rotation}")
            |> Enum.map(fn quality_and_format ->
              {file_name, "#{region}/#{size}/#{rotation}/#{quality_and_format}"}
            end)
          end)
          |> List.flatten()
        end)
        |> List.flatten()
      end)
      |> List.flatten()
    end)
    |> List.flatten()
  end
end
