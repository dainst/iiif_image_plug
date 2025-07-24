# defmodule IIIFImagePlug.V3.CacheHeadersTest do
#   use ExUnit.Case, async: true

#   import Plug.Test
#   import Plug.Conn, only: [get_resp_header: 2]

#   alias IIIFImagePlug.V3.Options

#   @sample_jpg "bentheim_mill.jpg"

#   # Create test plugs with different cache configurations
#   defmodule StaticCachePlug do
#     use IIIFImagePlug.V3

#     @impl true
#     def identifier_to_path(identifier) do
#       {:ok, "test/images/#{identifier}"}
#     end

#     @impl true
#     def host(), do: "localhost"

#     @impl true
#     def port(), do: 4001
#   end

#   defmodule DynamicCachePlug do
#     use IIIFImagePlug.V3

#     @impl true
#     def identifier_to_path(identifier) do
#       # Map test identifiers to real test images
#       case identifier do
#         "public_image.jpg" -> {:ok, "test/images/bentheim_mill.jpg"}
#         "private_image.jpg" -> {:ok, "test/images/bentheim_mill.jpg"}
#         "override_image.jpg" -> {:ok, "test/images/bentheim_mill.jpg"}
#         _ -> {:ok, "test/images/#{identifier}"}
#       end
#     end

#     @impl true
#     def host(), do: "localhost"

#     @impl true
#     def port(), do: 4001
#   end

#   describe "static cache control" do
#     test "sets cache-control header when configured" do
#       opts = %Options{
#         cache_control: "public, max-age=31536000, immutable"
#       }

#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "does not set cache-control header when not configured" do
#       opts = %Options{}

#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       # When no cache control is configured, the IIIF plug should not set any cache headers
#       # (though the test environment might set its own defaults)
#       cache_control_headers = get_resp_header(conn, "cache-control")
#       # Just ensure we didn't set any long-term caching headers
#       refute Enum.any?(cache_control_headers, &String.contains?(&1, "max-age=31536000"))
#     end
#   end

#   describe "dynamic cache control via callback" do
#     setup do
#       callback = fn
#         "public_image.jpg" -> "public, max-age=86400"
#         "private_image.jpg" -> "private, max-age=3600"
#         _ -> nil
#       end

#       {:ok, opts: %Options{identifier_to_cache_control_callback: callback}}
#     end

#     test "sets cache-control header based on identifier callback", %{opts: opts} do
#       conn =
#         conn(:get, "/public_image.jpg/full/max/0/default.jpg")
#         |> DynamicCachePlug.call(DynamicCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
#     end

#     test "sets different cache-control for private images", %{opts: opts} do
#       conn =
#         conn(:get, "/private_image.jpg/full/max/0/default.jpg")
#         |> DynamicCachePlug.call(DynamicCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["private, max-age=3600"]
#     end

#     test "callback returning nil results in no cache header", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.jpg")
#         |> DynamicCachePlug.call(DynamicCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       # When callback returns nil, no custom cache headers should be set
#       cache_control_headers = get_resp_header(conn, "cache-control")
#       # Ensure none of our custom cache headers are present
#       refute "public, max-age=86400" in cache_control_headers
#       refute "private, max-age=3600" in cache_control_headers
#     end
#   end

#   describe "callback takes precedence over static config" do
#     test "uses callback value when both are configured" do
#       callback = fn
#         "override_image.jpg" -> "no-cache"
#         _ -> nil
#       end

#       opts = %Options{
#         cache_control: "public, max-age=31536000",
#         identifier_to_cache_control_callback: callback
#       }

#       conn =
#         conn(:get, "/override_image.jpg/full/max/0/default.jpg")
#         |> DynamicCachePlug.call(DynamicCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["no-cache"]
#     end
#   end

#   describe "cache headers work with different output formats" do
#     setup do
#       {:ok, opts: %Options{cache_control: "public, max-age=31536000, immutable"}}
#     end

#     test "sets cache headers for JPEG output", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "sets cache headers for PNG output", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.png")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "sets cache headers for WebP output", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.webp")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "sets cache headers for TIFF output (buffered)" do
#       opts = %Options{
#         cache_control: "public, max-age=31536000, immutable",
#         temp_dir: :buffer,
#         extra_formats: [:tif]
#       }

#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/default.tif")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end
#   end

#   describe "cache headers with different image operations" do
#     setup do
#       {:ok, opts: %Options{cache_control: "public, max-age=31536000, immutable"}}
#     end

#     test "sets cache headers for region extraction", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/100,100,200,200/max/0/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "sets cache headers for size operations", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/200,200/0/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "sets cache headers for rotation operations", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/90/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end

#     test "sets cache headers for quality operations", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/full/max/0/gray.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200
#       assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
#     end
#   end

#   describe "no cache headers for non-image responses" do
#     setup do
#       {:ok, opts: %Options{cache_control: "public, max-age=31536000, immutable"}}
#     end

#     test "does not set cache headers for info.json", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}/info.json")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 200

#       # The test plug seems to set default headers, we just care that our custom headers aren't set
#       cache_control_headers = get_resp_header(conn, "cache-control")
#       refute "public, max-age=31536000, immutable" in cache_control_headers
#     end

#     test "does not set cache headers for redirects", %{opts: opts} do
#       conn =
#         conn(:get, "/#{@sample_jpg}")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :set]
#       assert conn.status == 302
#       # Redirects should not have our custom cache headers
#       cache_control_headers = get_resp_header(conn, "cache-control")
#       refute "public, max-age=31536000, immutable" in cache_control_headers
#     end

#     test "does not set cache headers for errors", %{opts: opts} do
#       conn =
#         conn(:get, "/nonexistent.jpg/full/max/0/default.jpg")
#         |> StaticCachePlug.call(StaticCachePlug.init(opts))

#       assert conn.state in [:sent, :chunked]
#       assert conn.status == 404

#       # The test plug seems to set default headers, we just care that our custom headers aren't set
#       cache_control_headers = get_resp_header(conn, "cache-control")
#       refute "public, max-age=31536000, immutable" in cache_control_headers
#     end
#   end
# end
