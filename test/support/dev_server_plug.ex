defmodule DevServerPlug do
  use Plug.Router
  use Plug.Debugger

  plug(:match)
  plug(:dispatch)

  forward("/",
    to: IIIFImagePlug.V3,
    init_opts: %{
      scheme: :http,
      host: "localhost",
      port: 4000,
      prefix: "/",
      identifier_to_path_callback: &DevCallbacks.identifier_to_path/1,
      identifier_to_rights_callback: &DevCallbacks.get_rights/1
    }
  )
end
