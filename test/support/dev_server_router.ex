defmodule DevServerRouter do
  use Plug.Router
  use Plug.Debugger
  import DevServerHelper, only: [set_url_and_port: 2]

  @moduledoc false

  plug(:set_url_and_port)
  plug(:match)
  plug(:dispatch)

  forward("/",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      identifier_to_rights_callback: &DevServerHelper.get_rights/1
    }
  )
end
