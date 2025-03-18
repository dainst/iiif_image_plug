defmodule IIIFImagePlug.V3Test do
  use ExUnit.Case, async: true
  doctest IIIFImagePlug.V3

  import Plug.Test
  import ExUnit.CaptureLog

  alias Vix.Vips.Operation
  alias Vix.Vips.Image

  @opts DevServerPlug.init([])
  @sample_image_name "bentheim_mill.jpg"

  test "returns the info.json for the sample image image" do
    conn = conn(:get, "/#{@sample_image_name}/info.json")

    conn = DevServerPlug.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 200

    response = Jason.decode!(conn.resp_body)

    assert %{
             "@context" => "http://iiif.io/api/image/3/context.json",
             "extraFormats" => ["png", "tif"],
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
             "height" => 400,
             "id" => "http://localhost/bentheim_mill.jpg",
             "maxArea" => 100_000_000,
             "maxHeight" => 10000,
             "maxWidth" => 10000,
             "preferredFormat" => ["webp", "jpg"],
             "profile" => "level2",
             "protocol" => "http://iiif.io/api/image",
             "rights" => "https://creativecommons.org/publicdomain/zero/1.0/",
             "type" => "ImageServer3",
             "width" => 400
           } = response
  end

  test "returns 404 for unknown identifier" do
    unknown_identifier = "nope.jpg"

    conn = conn(:get, "/#{unknown_identifier}/info.json")

    conn = DevServerPlug.call(conn, @opts)

    assert conn.state == :sent
    assert conn.status == 404

    response = Jason.decode!(conn.resp_body)

    msg = "No file with identifier '#{unknown_identifier}'."

    assert %{"description" => ^msg} = response
  end

  test "returns 500 when attempting to open unsupported file and error gets logged" do
    unsupported = "not_an_image.txt"

    conn = conn(:get, "/#{unsupported}/info.json")

    log =
      capture_log(fn ->
        conn = DevServerPlug.call(conn, @opts)
        assert conn.state == :sent
        assert conn.status == 500
      end)

    assert log =~ "File matching identifier '#{unsupported}' could not be opened as an image."
  end

  test "returns the image data of the sample image" do
    conn = conn(:get, "/#{@sample_image_name}/full/max/0/default.jpg")

    conn = DevServerPlug.call(conn, @opts)

    assert conn.state == :chunked
    assert conn.status == 200

    {:ok, from_file} = Image.new_from_file("test/images/#{@sample_image_name}")
    {:ok, from_response} = Image.new_from_buffer(conn.resp_body)

    assert Image.width(from_file) == Image.width(from_response)
    assert Image.height(from_file) == Image.height(from_response)

    assert Operation.avg!(from_file) |> Float.round(3) ==
             Operation.avg!(from_response) |> Float.round(3)
  end
end
