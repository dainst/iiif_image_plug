import Config

config :iiif_image_plug,
  max_width: 10000,
  max_height: 10000,
  max_area: 10000 * 10000

import_config "#{config_env()}.exs"
