defmodule IIIFImagePlug.V3Test do
  alias IIIFImagePlug.V3
  use ExUnit.Case, async: true
  doctest IIIFImagePlug.V3

  import Plug.Test
  import ExUnit.CaptureLog

  @opts DevServerRouter.init([])

  @sample_jpg_name "bentheim_mill.jpg"
  @sample_pyramid_tif_name "bentheim_mill_pyramid.tif"
  @sample_png_for_validator "official_test_image.png"
  @paths_root "test/images/test_paths"
  @paths_pyramid_root "test/images/test_paths_pyramid"

  test "raises if no identifier to path callback is provided" do
    assert_raise RuntimeError,
                 "Missing callback used to construct file path from identifier.",
                 fn -> V3.init(%{}) end
  end

  test "does not raise if identifier to path callback is provided" do
    assert %IIIFImagePlug.V3.Settings{
             scheme: nil,
             host: nil,
             port: nil,
             max_width: 600,
             max_height: 400,
             max_area: 240_000,
             preferred_formats: [:jpg],
             extra_formats: [:webp, :png, :tif],
             identifier_to_rights_callback: nil,
             identifier_to_part_of_callback: nil,
             identifier_to_see_also_callback: nil,
             identifier_to_service_callback: nil,
             status_callbacks: %{}
           } = V3.init(%{identifier_to_path_callback: &DevServerHelper.identifier_to_path/1})
  end

  test "returns the info.json for the sample image image" do
    conn = conn(:get, "/#{@sample_jpg_name}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert %{
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
             "id" => "http://localhost:4000/bentheim_mill.jpg",
             "maxArea" => 240_000,
             "maxHeight" => 400,
             "maxWidth" => 600,
             "preferredFormat" => ["jpg"],
             "profile" => "level2",
             "protocol" => "http://iiif.io/api/image",
             "rights" => "https://creativecommons.org/publicdomain/zero/1.0/",
             "type" => "ImageService3",
             "width" => 500
           } = response
  end

  test "returns the correct info.json on non-root paths for the sample image image" do
    conn = conn(:get, "/some/nested/route/#{@sample_jpg_name}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert %{
             "id" => "http://localhost:4000/some/nested/route/bentheim_mill.jpg"
           } = response
  end

  test "returns the info.json for the sample image image tif" do
    conn = conn(:get, "/#{@sample_pyramid_tif_name}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert %{
             "id" => "http://localhost:4000/bentheim_mill_pyramid.tif",
             "sizes" => [%{"height" => 150, "type" => "Size", "width" => 250}]
           } = response
  end

  test "redirects to info.json if only identifier is provided" do
    conn = conn(:get, "/#{@sample_pyramid_tif_name}")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :set
    assert conn.status == 302

    assert ["http://localhost:4000/bentheim_mill_pyramid.tif/info.json"] =
             Plug.Conn.get_resp_header(conn, "location")
  end

  test "sends 404 for unknown paths" do
    conn = conn(:get, "/this/wont/do")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404

    response = Jason.decode!(conn.resp_body)

    assert %{"path_info" => ["this", "wont", "do"], "reason" => "Unknown path."} = response
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

    response = Jason.decode!(conn.resp_body)

    assert %{"reason" => "not found from custom 404 handler"} = response
  end

  describe "image data endpoint" do
    test "returns the correct image data of the sample jpg image" do
      generate_path_list(@paths_root)
      # |> IO.inspect()
      |> Enum.each(fn path ->
        conn = conn(:get, "/#{@sample_jpg_name}/#{path}" |> URI.encode())

        conn = DevServerRouter.call(conn, @opts)

        if String.ends_with?(path, "tif") do
          assert conn.state == :sent
        else
          assert conn.state == :chunked
        end

        assert conn.status == 200

        {:ok, from_file} = Image.open("#{@paths_root}/#{path}")
        {:ok, from_response} = Image.from_binary(conn.resp_body)

        assert {:ok, +0.0, _image} = Image.compare(from_file, from_response)
      end)
    end

    test "returns the correct image data of the sample pyramid tif image" do
      generate_path_list(@paths_pyramid_root)
      # |> IO.inspect()
      |> Enum.each(fn path ->
        conn = conn(:get, "/#{@sample_pyramid_tif_name}/#{path}" |> URI.encode())

        conn = DevServerRouter.call(conn, @opts)

        if String.ends_with?(path, "tif") do
          assert conn.state == :sent
        else
          assert conn.state == :chunked
        end

        assert conn.status == 200

        {:ok, from_file} = Image.open("#{@paths_pyramid_root}/#{path}")
        {:ok, from_response} = Image.from_binary(conn.resp_body)

        if path == "full/!200,250/0/default.jpg" do
          assert {:ok, quality, _image} = Image.compare(from_file, from_response)
          assert quality < 0.1
        else
          assert {:ok, +0.0, _image} = Image.compare(from_file, from_response)
        end
      end)
    end

    test "returns the correct image data of the rectangle provided by the official validator" do
      conn = conn(:get, "/#{@sample_png_for_validator}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :chunked
      assert conn.status == 200
    end

    # test "square on a square image" do
    #   conn = conn(:get, "/#{@sample_png_for_validator}/square/max/0/default.jpg")

    #   conn = DevServerRouter.call(conn, @opts)

    #   assert conn.state == :chunked
    #   assert conn.status == 200

    #   {:ok, from_file} = Image.open("test/images/#{@sample_png_for_validator}")
    #   {:ok, from_response} = Image.from_binary(conn.resp_body)

    #   assert Image.width(from_file) == Image.width(from_response)
    #   assert Image.height(from_file) == Image.height(from_response)
    # end

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

    test "returns 400 for unsupported quality or format" do
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.txt")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response
    end
  end

  defp generate_path_list(root) do
    File.ls!(root)
    |> Enum.map(fn region ->
      File.ls!("#{root}/#{region}")
      |> Enum.map(fn size ->
        File.ls!("#{root}/#{region}/#{size}")
        |> Enum.map(fn rotation ->
          File.ls!("#{root}/#{region}/#{size}/#{rotation}")
          |> Enum.map(fn quality_and_format ->
            "#{region}/#{size}/#{rotation}/#{quality_and_format}"
          end)
        end)
        |> List.flatten()
      end)
      |> List.flatten()
    end)
    |> List.flatten()
  end
end
