defmodule IIIFServer do
  use Plug.Router
  use Plug.Debugger

  plug(:match)
  plug(:dispatch)

  forward("/image",
    to: IIIFPlug.V3,
    init_opts: %{
      scheme: :http,
      server: "localhost",
      prefix: "/image",
      max_height: 5000,
      max_width: 10000,
      max_area: 5000 * 5000
    }
  )

  match _ do
    send_resp(conn, 404, "404 Not Found")
  end
end
