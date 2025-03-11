defmodule IIIFImagePlug.Application do
  use Application

  require Logger

  def start(_type, _args) do
    children = [
      {Bandit, plug: Server}
    ]

    opts = [strategy: :one_for_one, name: IIIFImagePlug.Supervisor]

    Logger.info("Starting application...")
    Supervisor.start_link(children, opts)
  end
end
