defmodule Server do
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
      identifier_to_path_callback: &ImageStore.identifier_to_path/1,
      status_callbacks: %{
        404 => &ImageStore.handle_404/2
      }
    }
  )

  # match _ do
  #   send_resp(conn, 404, "404 Not Found")
  # end
end
