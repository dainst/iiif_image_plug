defmodule DevServerRouter do
  use Plug.Router
  use Plug.Debugger

  @moduledoc false

  plug(CORSPlug, origin: ["*"])
  plug(:match)
  plug(:dispatch)

  forward("/some/nested/route",
    to: DefaultPlug,
    init_opts: %{}
  )

  forward("/buffered_tiffs",
    to: DefaultPlug,
    init_opts: %{
      temp_dir: :buffer
    }
  )

  forward("/no_extra_formats",
    to: DefaultPlug,
    init_opts: %{
      extra_formats: []
    }
  )

  forward("/extra_info",
    to: ExtraInfoPlug,
    init_opts: %{}
  )

  forward("/custom_404_route",
    to: Custom404Plug,
    init_opts: %{}
  )

  forward("/",
    to: DefaultPlug,
    init_opts: %{}
  )
end
