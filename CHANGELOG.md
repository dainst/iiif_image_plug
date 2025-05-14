# Changelog

## 0.5.0
- Changed override options `:port`, `:host` and `:scheme` into callbacks to make values configurable at runtime.
- Fixed "height" key typo in `info.json`
- Fixed handling of files that contain exif orientation metadata tags.

## 0.4.0

Made some minor additional changes to align with IIIF image API spec:
- Fixed the static value for key "type" in the `info.json`.
- Return 404 status code for invalid paths (instead of the 400 in the initial implementation).
- Redirect to `info.json` if the request ends with the identifier (i.e. from `/path/to/plug/my-image` to `/path/to/plug/my-image/info.json`).
- Reintroduced override options `:port`, `:host` and `:scheme` for proxy scenarios.

## 0.3.1

Fixed error with pyramid page optimization was not applied if no `vscale` was requested. This caused a fallback to full image processing.

## 0.3.0

Removed the `:scheme`, `:host`, `:port` and `:prefix` options, those are now evaluated directly from the [`%Plug.Conn{}`](https://hexdocs.pm/plug/Plug.Conn.html).

## 0.2.0

Added optimization for pyramid tiffs:
- The `info.json` may now contain the [sizes](https://iiif.io/api/image/3.0/#53-sizes) property, if the identifier refers to a pyramid image.
- When image data is requested based off an pyramid image, the plug now should select the best matching image from the pyramid and apply an adjusted transformation on that preprocessed lower resolution image (instead of always working on the maximum resolution).

## 0.1.0

Minimal viable v3 plug.