defmodule IIIFImagePlug.V3.Info do
  import Plug.Conn
  alias IIIFImagePlug.V3.RequestError
  alias Plug.Conn
  alias Vix.Vips.Image

  alias IIIFImagePlug.V3.{
    InfoRequest,
    Options
  }

  @moduledoc false

  @doc """
  Creates the data for an image information request (`info.json`) for the given `identifier`.

  ## Returns

  - `{conn, metadata}` on success, where `conn` is an updated `Plug.Conn` struct (if the plug defines its own
  response headers for the `identifier`) and `metadata` is a map in the `info.json` structure to be encoded and sent as a response content.
  - `{:error, reason}` otherwise.
  """
  def generate_image_info(%Conn{} = conn, identifier, %Options{} = options, using_module)
      when is_binary(identifier) do
    with {
           :ok,
           %InfoRequest{
             path: path,
             rights: rights,
             part_of: part_of,
             see_also: see_also,
             service: service,
             response_headers: headers
           }
         } <-
           using_module.info_request(identifier),
         {:file_exists, true} <- {:file_exists, File.exists?(path)},
         {:file_opened, {:ok, file}} <- {:file_opened, Image.new_from_file(path)} do
      {
        :ok,
        {
          Enum.reduce(headers, conn, fn {key, value}, acc ->
            put_resp_header(acc, key, value)
          end),
          %{
            "@context": "http://iiif.io/api/image/3/context.json",
            id: "#{construct_image_id(conn, identifier, using_module)}",
            type: "ImageService3",
            protocol: "http://iiif.io/api/image",
            width: Image.width(file),
            height: Image.height(file),
            profile: "level2",
            maxHeight: options.max_height,
            maxWidth: options.max_width,
            maxArea: options.max_area,
            extra_features: [
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
            preferredFormat: options.preferred_formats,
            extraFormats: options.extra_formats,
            extraQualities: [:color, :gray, :bitonal]
          }
          |> maybe_add_info(:rights, rights)
          |> maybe_add_info(:partOf, part_of)
          |> maybe_add_info(:seeAlso, see_also)
          |> maybe_add_info(:service, service)
          |> maybe_add_sizes(file, path)
        }
      }
    else
      {:error, %RequestError{}} = error ->
        error

      {:file_exists, false} ->
        {:error, :no_file}

      {:file_opened, _} ->
        {:error, :no_image_file}
    end
  end

  @doc """
  Returns a URI (IIIF image ID) for the given identifier.
  """
  def construct_image_id(
        %Conn{} = conn,
        identifier,
        using_module
      )
      when is_binary(identifier) do
    scheme = using_module.scheme() || conn.scheme
    host = using_module.host() || conn.host
    port = using_module.port() || conn.port

    Enum.join([
      scheme,
      "://",
      host,
      if(port != nil, do: ":#{port}", else: ""),
      if(conn.script_name != [], do: Path.join(["/"] ++ conn.script_name), else: ""),
      "/",
      identifier
    ])
  end

  defp maybe_add_info(info, _key, value) when is_nil(value) or value == [], do: info
  defp maybe_add_info(info, key, value), do: Map.put(info, key, value)

  defp maybe_add_sizes(info, base_image, path) do
    page_count =
      try do
        Image.n_pages(base_image)
      rescue
        _ -> 1
      end

    if page_count > 1 do
      last_page = page_count - 1

      sizes =
        0..last_page
        |> Stream.map(fn page ->
          {:ok, page_image} = Image.new_from_file(path, page: page)

          width = Image.width(page_image)
          height = Image.height(page_image)

          %{
            type: "Size",
            width: width,
            height: height
          }
        end)
        |> Stream.reject(fn %{width: width} ->
          width == Image.width(base_image)
        end)
        |> Enum.sort_by(fn %{width: width} -> width end)

      Map.put(info, :sizes, sizes)
    else
      info
    end
  end
end
