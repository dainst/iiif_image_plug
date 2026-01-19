[![CI status](https://github.com/dainst/iiif_image_plug/actions/workflows/ci.yml/badge.svg)](https://github.com/dainst/iiif_image_plug/actions/workflows/ci.yml)

- [hex package](https://hex.pm/packages/iiif_image_plug)
- [hex documentation](https://hexdocs.pm/iiif_image_plug/)

# IIIF Image Plug

An Elixir [plug](https://hexdocs.pm/plug/readme.html) implementing the _International Image Interoperability Framework_ ([IIIF](https://iiif.io/)) image API specification. 

- The goal of IIIF is to define a standardised REST API for serving high resolution images (art, photographes or archival material published by museums, universities and similar institutions).
- This plug library needs you to define a mapping between image identifier (used in the REST API) and file system path, and will then do the image transformations based on the other request parameters for you.
- There exist [several](https://iiif.io/get-started/iiif-viewers/) generic Javascript IIIF viewers that utilize this API to allow for optimized viewing (dynamic loading of parts of the image data based on zoom level/viewport).
- WebGIS Javascript libraries like [leaflet](https://github.com/mejackreed/Leaflet-IIIF) or [OpenLayers](https://openlayers.org/en/latest/examples/iiif.html) support IIIF in one way or the other.
- For the time beeing only (the current) Image API 3.0 is implemented, check out the IIIF [documentation](https://iiif.io/api/image/3.0/) for its capabilities.
- The IIIF image API implemented by this library is just one (the foundational) of currently six API standards the IIIF community defines for serving multimedia content and metadata.
- The image processing is handled by [libvips](https://www.libvips.org/) via [Vix](https://hex.pm/packages/vix).

## Installation 

The package can be installed
by adding `iiif_image_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:iiif_image_plug, "~> 0.7.0"}
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
  def info_metadata(identifier) do
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
          %IIIFImagePlug.V3.InfoRequestMetadata{
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
  def data_metadata(identifier) do
    # The second required callback lets you inject some metadata 
    # from your application into the plug when it is responding to
    # an actual image data request for a specific `identifier`. As 
    # with `info_metadata/1`, the only required field is `:path`, which 
    # tells the plug the file system path matching the given `identifier`.
    MyApp.ContextModule.get_image_path(identifier)
    |> case do
      {:ok, path} ->
        {
          :ok,
          %IIIFImagePlug.V3.DataRequestMetadata{
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
either set the correct headers in your `info_metadata/1` or `data_metadata/1` implementation or configure the appropriate headers in a plug
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

## Advanced usage

### Input optimization

The performance is greatly improved if you provide your images in more than one resolution. This can be accomplished by providing image pyramids. Using `vips8` you can generate a TIF file pyramid:

```bash
vips tiffsave input.jpg output_pyramid.tif --compression deflate --tile --tile-width 256 --tile-height 256 --pyramid
```

The same can be achieved in Elixir with [Vix](https://hex.pm/packages/vix):

```elixir
{:ok, file} = Image.new_from_file("input.jpg")

Operation.tiffsave(file, "output_pyramid.tif",
    pyramid: true,
    "tile-height": 256,
    "tile-width": 256,
    tile: true,
    compression: :VIPS_FOREIGN_TIFF_COMPRESSION_DEFLATE
)
```

This will generate a single file that contains multiple pages of decreasing resolution:
![Image pyramid example image](additional_docs/image_pyramid.png)

The IIIF Image plug will automatically evaluate these pages and select the best matching for the requested scaling operation - thus avoiding to work on the full scale image where possible.

### Output optimization

Some image formats can not be streamed directly and are written to a temporary file by default, see the documentation for the `IIIFImagePlug.V3.Options` module.

### Caching

You can implement your own caching strategy using the optional `info_call/1`, `info_response/2`, `data_call/1` and `data_response/3` callbacks. Have a look at the `*_call/1` functions' documentation for two naive examples.

### Alternatives to this library

The plug aims to implement the "level 2" [compliance](https://iiif.io/api/image/3.0/compliance) for the IIIF image API.

If you only want to provide "level 0" data (the most basic required for tiled viewers), you can preprocess your input images beforehand and serve them as static assets (without any specialized library necessary at runtime).

There exist several [resources](https://training.iiif.io/dhsi/day-one/level-0-static.html) on how to do this.

Running `vips`:

```bash
vips dzsave input.jpg preprocessed_out --layout iiif3 --depth onetile --overlap 0 --suffix .jpg
```

This will create a directory "preprocessed_out" that contains a bunch of directories (each corresponding to a possible "region" parameter) and a basic `info.json` file. These can then be served as static assets.

Again, Vix provides the same functionality in Elixir with [Vix.Vips.Operation.dzsave/3](https://hexdocs.pm/vix/Vix.Vips.Operation.html#dzsave/3).
