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
      host: &DevServerHelper.get_host/0,
      port: &DevServerHelper.get_port/0,
      identifier_to_rights_callback: &DevServerHelper.get_rights/1
    }
  )

  forward("/custom_404_route",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      host: &DevServerHelper.get_host/0,
      port: &DevServerHelper.get_port/0,
      status_callbacks: %{404 => &DevServerHelper.handle_404/2}
    }
  )

  forward("/buffered_tiffs",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      host: &DevServerHelper.get_host/0,
      port: &DevServerHelper.get_port/0,
      temp_dir: :buffer
    }
  )

  forward("/no_extra_formats",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      host: &DevServerHelper.get_host/0,
      port: &DevServerHelper.get_port/0,
      extra_formats: []
    }
  )

  forward("/",
    to: IIIFImagePlug.V3,
    init_opts: %{
      identifier_to_path_callback: &DevServerHelper.identifier_to_path/1,
      host: &DevServerHelper.get_host/0,
      port: &DevServerHelper.get_port/0,
      identifier_to_rights_callback: &DevServerHelper.get_rights/1
    }
  )
end
