# Changelog

## 0.2.0

Added optimization for pyramid tiffs:
- The `info.json` may now contain the [sizes](https://iiif.io/api/image/3.0/#53-sizes) property, if the identifier refers to a pyramid image.
- When image data is requested based off an pyramid image, the plug now should select the best matching image from the pyramid and apply an adjusted transformation on that preprocessed lower resolution image (instead of always working on the maximum resolution).

## 0.1.0

Minimal viable v3 plug.