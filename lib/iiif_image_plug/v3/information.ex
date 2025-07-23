defmodule IIIFImagePlug.V3.Information do
  import Plug.Conn
  alias Plug.Conn
  alias Vix.Vips.Image

  @moduledoc """
  This struct is used for generating an image's `info.json` that is being served by the `IIIFImagePlug.V3` plug.

  ## Fields

  - `:path` (required) your local file system path to the image file.
  - `:rights` (optional) the [rights](https://iiif.io/api/image/3.0/#56-rights) statement for the given image.
  - `:part_of` (optional) the _partOf_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:see_also` (optional) the _seeAlso_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  - `:service` (optional) the _service_ [linking property](https://iiif.io/api/image/3.0/#58-linking-properties) for the image.
  """

  @enforce_keys :path
  defstruct [:path, :rights, part_of: [], see_also: [], service: [], response_headers: []]

  @type t :: %__MODULE__{
          path: String.t(),
          rights: String.t() | nil,
          part_of: list(),
          see_also: list(),
          service: list()
        }

  @doc false
  def generate_image_info(conn, identifier, options, module) do
    with {
           :identifier,
           {
             :ok,
             %__MODULE__{
               path: path,
               rights: rights,
               part_of: part_of,
               see_also: see_also,
               service: service,
               response_headers: headers
             }
           }
         } <-
           {
             :identifier,
             module.identifier_info(identifier)
           },
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
            id: "#{construct_image_id(conn, identifier, module)}",
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
      {:identifier, _} ->
        {:error, :unknown_identifier}

      {:file_exists, false} ->
        {:error, :no_file}

      {:file_opened, _} ->
        {:error, :no_image_file}
    end
  end

  @doc false
  def construct_image_id(
        %Conn{} = conn,
        identifier,
        module
      )
      when is_binary(identifier) do
    scheme = module.scheme() || conn.scheme
    host = module.host() || conn.scheme
    port = module.port() || conn.port

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
