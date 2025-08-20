defmodule DevServerRouter do
  use Plug.Router
  use Plug.Debugger

  @moduledoc false
  alias IIIFImagePlug.V3.Options

  plug(CORSPlug, origin: ["*"])
  plug(:match)
  plug(:dispatch)

  forward("/some/nested/route",
    to: DefaultPlug,
    init_opts: %Options{}
  )

  forward("/buffered_tiffs",
    to: DefaultPlug,
    init_opts: %Options{
      temp_dir: :buffer,
      extra_formats: [:tif]
    }
  )

  forward("/no_extra_formats",
    to: DefaultPlug,
    init_opts: %Options{
      extra_formats: []
    }
  )

  forward("/extra_info",
    to: ExtraInfoPlug,
    init_opts: %Options{}
  )

  forward("/custom_404_route",
    to: Custom404Plug,
    init_opts: %Options{}
  )

  forward("/custom_response_headers",
    to: CustomResponseHeaderPlug,
    init_opts: %Options{}
  )

  forward("/proxy_setup",
    to: BehindProxyPlug,
    init_opts: %Options{}
  )

  forward("/restricted_access",
    to: CustomRequestErrorPlug,
    init_opts: %Options{}
  )

  forward("/content_type_override",
    to: ContentTypeOverridePlug,
    init_opts: %Options{}
  )

  forward("/custom_format_options",
    to: DefaultPlug,
    init_opts: %Options{
      format_options: %{
        jpg: [Q: 5, background: [255, 255, 0]],
        webp: [lossless: true],
        png: [bitdepth: 1]
      }
    }
  )

  forward("/",
    to: DefaultPlug,
    init_opts:
      if Mix.env() == :test do
        %Options{
          max_width: 600,
          max_height: 400,
          max_area: 600 * 400,
          extra_formats: [:webp, :png, :tif]
        }
      else
        %Options{}
      end
  )
end
