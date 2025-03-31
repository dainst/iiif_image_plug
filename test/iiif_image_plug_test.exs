defmodule IIIFImagePlug.V3Test do
  use ExUnit.Case, async: true
  doctest IIIFImagePlug.V3

  import Plug.Test
  import ExUnit.CaptureLog

  @opts DevServerRouter.init([])

  @sample_jpg_name "bentheim_mill.jpg"
  @sample_pyramid_tif_name "bentheim_mill_pyramid.tif"
  @paths_root "test/images/test_paths"

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
             "type" => "ImageServer3",
             "width" => 500
           } = response
  end

  test "returns 404 for unknown identifier" do
    unknown_identifier = "nope.jpg"

    conn = conn(:get, "/#{unknown_identifier}/info.json")

    conn = DevServerRouter.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404

    response = Jason.decode!(conn.resp_body)

    msg = "No file with identifier '#{unknown_identifier}'."

    assert %{"reason" => ^msg} = response
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

  describe "image data endpoint" do
    test "returns the correct image data of the sample jpg image" do
      generate_path_list()
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
      generate_path_list()
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

        {:ok, from_file} = Image.open("#{@paths_root}/#{path}")
        {:ok, from_response} = Image.from_binary(conn.resp_body)

        assert {:ok, +0.0, _image} = Image.compare(from_file, from_response)
      end)
    end

    test "returns 404 for unknown identifier" do
      unknown_identifier = "does_not_exist.jpg"
      conn = conn(:get, "/#{unknown_identifier}/full/max/0/default.jpg")

      conn = DevServerRouter.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 404

      response = Jason.decode!(conn.resp_body)

      msg = "No file with identifier '#{unknown_identifier}'."

      assert %{"reason" => ^msg} = response
    end

    test "returns 400 for invalid parameters" do
      conn = conn(:get, "/#{@sample_jpg_name}/nope/max/0/default.jpg")

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

      msg = "Could not find parse valid quality and format from 'default.txt'."

      assert %{"reason" => ^msg} = response
    end
  end

  defp generate_path_list() do
    File.ls!(@paths_root)
    |> Enum.map(fn region ->
      File.ls!("#{@paths_root}/#{region}")
      |> Enum.map(fn size ->
        File.ls!("#{@paths_root}/#{region}/#{size}")
        |> Enum.map(fn rotation ->
          File.ls!("#{@paths_root}/#{region}/#{size}/#{rotation}")
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
