[![CI status](https://github.com/dainst/iiif_image_plug/actions/workflows/ci.yml/badge.svg)](https://github.com/dainst/iiif_image_plug/actions/workflows/ci.yml)

- [hex package](https://hex.pm/packages/iiif_image_plug)
- [hex documentation](https://hexdocs.pm/iiif_image_plug/)

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
    {:iiif_image_plug, "~> 0.5.0"}
  ]
end
```

Assuming you want to serve IIIF in your plug based server at "/iiif/v3", add a forward route like this: 

```elixir
  forward("/iiif/v3", to: MyApp.IIIFPlug, init_opts: %IIIFImagePlug.V3.Options{})
```

For [Phoenix](https://www.phoenixframework.org/) it would be slightly different:

```elixir
  forward("/iiif/v3", MyApp.IIIFPlug, %IIIFImagePlug.V3.Options{})
```

For the complete list of plug options have a look at the module documentation for `IIIFImagePlug.V3.Options`.

A minimal plug implementation in your app might look like this:

```elixir
defmodule MyApp.IIIFPlug do
  use IIIFImagePlug.V3

  @impl true
  def identifier_to_path(identifier) do
    {:ok, "test/images/#{identifier}"}
  end
end
```

The callback function `identifier_to_path/1` is required and lets the plug map the IIIF [identifier](https://iiif.io/api/image/3.0/#21-image-request-uri-syntax) to an actual file path in your file system. A GET request `/iiif/v3/sample_image.jpg/info.json` would then cause the plug to look for an image file at `/mnt/my_app_images/sample_image.jpg` and return its metadata.

There are also a range of optional callbacks to customize your plug, again have a look at the module documentation for `IIIFImagePlug.V3`.

### CORS 

For your service to fully implement the API specification, you need to properly configure Cross-Origin Resource Sharing (CORS). This has to be done outside the context of this plug, one option could be to use the
[CorsPlug](https://hexdocs.pm/cors_plug/readme.html) library:

```elixir
(..)
  plug(CORSPlug, origin: ["*"])
  plug(:match)
  plug(:dispatch)

  forward("/",
    to: IIIFImagePlug.V3,
    init_opts: %{
      (..)
    }
  )
end
(..)
```

### Testing your endpoint 

Because this plug is just a library and only part of your overall application, you might want to test your service's IIIF compliance against the official validator:
- https://iiif.io/api/image/validator (web based)
- https://github.com/IIIF/image-validator (repository with python based validator)

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
