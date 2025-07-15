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
      temp_dir: :buffer
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

  forward("/",
    to: DefaultPlug,
    init_opts: %Options{
      max_width: 600,
      max_height: 400,
      max_area: 600 * 400
    }
  )
end
