defmodule DevServerRouter do
  use Plug.Router
  use Plug.Debugger

  @moduledoc false

  plug(CORSPlug, origin: ["*"])
  plug(:match)
  plug(:dispatch)

  forward("/some/nested/route",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      host: "localhost",
      port: 4000,
      identifier_to_rights_callback: &DevServerHelper.get_rights/1
    }
  )

  forward("/",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      host: "localhost",
      port: 4000,
      identifier_to_rights_callback: &DevServerHelper.get_rights/1
    }
  )
end
