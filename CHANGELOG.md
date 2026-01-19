# Changelog

## 1.0.0

Functionally the same as 0.7.0 with some small internal tweaks.

## 0.7.0

- __Breaking change__: Renamed `info_request/1` and `data_request/1` callbacks to `info_metadata/1` and `data_metadata/1` respectively, as well as the
associated structs to better align with new optional callbacks (see below).
- Added 4 optional callbacks that hook right into the start and end of both the information and data request handling. This was primarily added
to allow users to implement their own caching outside the plug. For more details see the `IIIFImagePlug.V3` docs.
- Added a plug option `:format_options` to set libvips save options for individual formats (encoding quality etc.). For more details see the `IIIFImagePlug.V3.Options` module documentation.

## 0.6.1
- Fixed handling of size parameters that did not contain a comma, a regression bug.
- Set proper content type headers for the requested image formats (thanks [neilberkman](https://github.com/neilberkman)). The automatic 
detection can be manually overriden by setting the header in your `data_request/1` implementation.

## 0.6.0
- Requested TIF image images are now written to a temporary file instead of to memory by default. 
- Also a new plug option `:temp_dir` was added to define a custom temporary directory path for the generated TIF files. In memory creation is still possible by passing `:buffer` instead.
- Added support for `:raw` and `:vips` image output formats.
- Rewrote the core V3 plug module to support the `use` keyword instead of having to pass callback functions as options.
- Removed the `rights`, `see_also`, `part_of` and `service` callbacks. Instead, you are now required to provide two callback functions: One for the `info.json` creation and one for the image data retrieval.
- HTTP response headers can now be set in the new info and data request callbacks based on the requested identifier (thanks [neilberkman](https://github.com/neilberkman)).

## 0.5.0
- Changed override options `:port`, `:host` and `:scheme` into callbacks to make values configurable at runtime.
- Fixed "height" key typo in `info.json`
- Fixed handling of files that contain exif orientation metadata tags.

## 0.4.0

Made some minor additional changes to align with the IIIF image API spec:
- Fixed the static value for key "type" in the `info.json`.
- Return 404 status code for invalid paths (instead of the 400 in the initial implementation).
- Redirect to `info.json` if the request ends with the identifier (i.e. from `/path/to/plug/my-image` to `/path/to/plug/my-image/info.json`).
- Reintroduced override options `:port`, `:host` and `:scheme` for proxy scenarios.

## 0.3.1

Fixed error where pyramid page optimization was not applied if no vertical scaling was requested. This caused a fallback to the default full scale processing.

## 0.3.0

Removed the `:scheme`, `:host`, `:port` and `:prefix` options, those are now evaluated directly from the [`%Plug.Conn{}`](https://hexdocs.pm/plug/Plug.Conn.html).

## 0.2.0

Added optimization for pyramid tiffs:
- The `info.json` may now contain the [sizes](https://iiif.io/api/image/3.0/#53-sizes) property, if the identifier refers to a pyramid image.
- When image data is requested based off an pyramid image, the plug now should select the best matching image from the pyramid and apply an adjusted transformation on that preprocessed lower resolution image (instead of always working on the maximum resolution).

## 0.1.0

Minimal viable v3 plug.
