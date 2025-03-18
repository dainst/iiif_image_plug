defmodule DevServerPlug do
  use Plug.Router
  use Plug.Debugger

  plug(:match)
  plug(:dispatch)

  forward("/",
    to: IIIFImagePlug.V3,
    init_opts: %{
      scheme: :http,
      server: "localhost",
      prefix: "/",
      identifier_to_path_callback: &DevCallbacks.identifier_to_path/1,
      identifier_to_rights_callback: &DevCallbacks.get_rights/1,
      status_callbacks: %{
        404 => &DevCallbacks.handle_404/2
      }
    }
  )

  # match _ do
  #   send_resp(conn, 404, "404 Not Found")
  # end
end
