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

  @expected_files_root "test/images/expected_results"

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
    test "returns the expected image data for the different test images" do
      get_expected_file_paths()
      |> Enum.each(fn {file_name, path} ->
        conn = conn(:get, "/#{file_name}/#{path}" |> URI.encode())

        conn = DevServerRouter.call(conn, @opts)

        if String.ends_with?(path, "tif") do
          assert conn.state == :sent
        else
          assert conn.state == :chunked
        end

        assert conn.status == 200

        {:ok, from_file} =
          Image.open("#{@expected_files_root}/#{file_name}/#{path}")

        {:ok, from_response} = Image.from_binary(conn.resp_body)

        cond do
          # TODO: Why is this not +0.0 for these two?
          file_name == "bentheim_mill_pyramid.tif" and path == "full/!200,250/0/default.jpg" ->
            assert {:ok, difference, _image} = Image.compare(from_file, from_response)
            assert difference < 0.1

          file_name == "official_test_image.png" and path == "square/max/0/default.png" ->
            assert {:ok, difference, _image} = Image.compare(from_file, from_response)
            assert difference < 0.1

          true ->
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
      conn = conn(:get, "/#{@sample_jpg_name}/full/max/0/default.txt")

      conn = DevServerRouter.call(conn, @opts)
      assert conn.state == :sent
      assert conn.status == 400

      response = Jason.decode!(conn.resp_body)

      assert %{"error" => "invalid_quality_and_format"} = response
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
