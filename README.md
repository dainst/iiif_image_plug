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
    {:iiif_image_plug, "~> 0.6.1"}
  ]
end
```

## Usage

Assuming you want to serve IIIF in your plug based server at "/iiif/v3", add a forward route like this: 

```elixir
  forward("/iiif/v3",
    to: MyApp.IIIFPlug,
    init_opts: %IIIFImagePlug.V3.Options{}
  )
```

For [Phoenix](https://www.phoenixframework.org/) it would look slightly different:

```elixir
  forward("/iiif/v3", MyApp.IIIFPlug, %IIIFImagePlug.V3.Options{})
```

### Example plug

A plug implementation may look something like this:

```elixir
defmodule MyApp.IIIFPlug do
  use IIIFImagePlug.V3

  # There are two required callbacks you have to implement, plus 
  # several optional ones. See the `IIIFImagePlug.V3` 
  # documentation for more.

  @impl true
  def info_request(identifier) do
    # The first required callback lets you inject some metadata 
    # from your application into the plug when it is responding to
    # an information request (info.json) for a specific `identifier`. 
    # The only required field is `:path`, which tells the plug the 
    # file system path matching the given `identifier`.

    MyApp.ContextModule.get_image_metadata(identifier)
    |> case do
      %{path: path, rights_statement: rights} ->
        {
          :ok,
          %IIIFImagePlug.V3.InfoRequest{
            path: path,
            rights: rights
          }
        }
      {:error, :not_found} ->
        {
          :error,
          %IIIFImagePlug.V3.RequestError{
            status_code: 404,
            msg: :not_found
          }
        }
    end
  end

  @impl true
  def data_request(identifier) do
    # The second required callback lets you inject some metadata 
    # from your application into the plug when it is responding to
    # an actual image data request for a specific `identifier`. As 
    # with `info_request/1`, the only required field is `:path`, which 
    # tells the plug the file system path matching the given `identifier`.
    MyApp.ContextModule.get_image_path(identifier)
    |> case do
      {:ok, path} ->
        {
          :ok,
          %IIIFImagePlug.V3.DataRequest{
            path: path,      
            response_headers: [
              {"cache-control", "public, max-age=31536000, immutable"}
            ]
          }
        }
      {:error, :not_found} ->
        {
          :error,
          %IIIFImagePlug.V3.RequestError{
            status_code: 404,
            msg: :not_found
          }
        }
    end
  end
```

### CORS 

For your service to fully implement the API specification, you need to properly configure Cross-Origin Resource Sharing (CORS). You could
either set the correct headers in your `info_request/1` or `data_request/1` implementation or configure the appropriate headers in a plug
before this one ([cors_plug ](https://hex.pm/packages/cors_plug) was used in this example):

```elixir
(..)
  plug(CORSPlug, origin: ["*"])
  plug(:match)
  plug(:dispatch)

  forward("/",
    to: MyApp.IIIFPlug,
    init_opts: (..)
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

The metadata of the main sample file [test/images/bentheim.jpg](test/images/bentheim.jpg) can now be accessed at http://localhost:4000/bentheim.jpg/info.json:

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

The sample image can be viewed at http://localhost:4000/bentheim.jpg/full/max/0/default.jpg and you can start experimenting with the IIIF API parameters.

![Jacob van Ruisdael. Gezicht op kasteel Bentheim, circa 1653](test/images/bentheim.jpg)