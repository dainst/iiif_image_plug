# IIIF Image Plug

An Elixir [plug](https://hexdocs.pm/plug/readme.html) implementing the _International Image Interoperability Framework_ ([IIIF](https://iiif.io/)) image API specification. 

- The goal of IIIF is to define a standardised REST API for serving high resolution images (art, photographes or archival material published by museums, universities and similar institutions).
- There exist [several](https://iiif.io/get-started/iiif-viewers/) generic Javascript IIIF viewers that utilize this API to allow for optimized viewing (dynamic loading of parts of the image data based on zoom level/viewport).
- WebGIS Javascript libraries like [leaflet](https://github.com/mejackreed/Leaflet-IIIF) or [OpenLayers](https://openlayers.org/en/latest/examples/iiif.html) support IIIF in one way or the other.
- For the time beeing only (the current) Image API 3.0 is implemented, check out the IIIF [documentation](https://iiif.io/api/image/3.0/) for its capabilities.
- The image processing is handled by [libvips](https://www.libvips.org/) via [Vix](https://hex.pm/packages/vix).

## Installation 

The package can be installed
by adding `iiif_image_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:iiif_image_plug, "~> 0.2.0"}
  ]
end
```

## Usage

Assuming you want to serve IIIF in your plug based server at "/iiif/v3", add a forward route like this: 

```elixir
  forward("/iiif/v3",
    to: IIIFImagePlug.V3,
    init_opts: %{
      scheme: :http,
      host: "localhost",
      port: 4000,
      prefix: "/iiif/v3",
      identifier_to_path_callback: &ImageStore.identifier_to_path/1
    }
  )
```

### Phoenix
For [Phoenix](https://www.phoenixframework.org/) it would look slightly different:

```elixir
  forward("/iiif/v3", IIIFImagePlug.V3, %{
    scheme: :http,
    host: "localhost",
    port: 4000,
    prefix: "/api/image/iiif/v3",
    identifier_to_path_callback: &ImageStore.identifier_to_path/1
  })
```

The option `:identifier_to_path_callback` lets the plug map the IIIF [identifier](https://iiif.io/api/image/3.0/#21-image-request-uri-syntax) to an actual file path in your file system. 

`ImageStore.identifier_to_path/1` in this case might look something like this:

```elixir
  def identifier_to_path(identifier) do
    "/mnt/my_app_images/#{identifier}"
  end
```

A GET request `/iiif/v3/sample_image.jpg/info.json` would then cause the plug to look for an image file at `/mnt/my_app_images/sample_image.jpg` and return its metadata.

The other options above `:scheme`, `:host`, `:port` and `:prefix` are used to generate the image's `id` field in its `info.json` (see IIIF [docs](https://iiif.io/api/image/3.0/#51-image-information-request)).

For the complete list of plug options have a look at the module documentation.

## Development

This repository comes with a minimalistic server, run the server with:

```
iex -S mix run
```

The metadata of the main sample file can now be accessed at http://127.0.0.1:4000/bentheim.jpg/info.json:

```json
{
    "id": "http://localhost:4000/bentheim.jpg",
    "profile": "level2",
    "type": "ImageServer3",
    "protocol": "http://iiif.io/api/image",
    "rights": "https://creativecommons.org/publicdomain/zero/1.0/",
    "width": 3000,
    "height": 2279,
    "@context": "http://iiif.io/api/image/3/context.json",
    "maxHeight": 10000,
    "maxWidth": 10000,
    "maxArea": 100000000,
    "extra_features": [
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
    "preferredFormat": [
        "jpg"
    ],
    "extraFormats": [
        "webp",
        "png",
        "tif"
    ],
    "extraQualities": [
        "color",
        "gray",
        "bitonal"
    ]
}
```

The image data of the sample file can be viewed at http://127.0.0.1:4000/bentheim.jpg/full/max/0/default.jpg and you are able to play around with the IIIF API parameters.