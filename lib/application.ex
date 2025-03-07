defmodule IIIFPlug.Application do
  use Application

  require Logger

  def start(_type, _args) do
    children = [
      {Bandit, plug: IIIFServer}
    ]

    opts = [strategy: :one_for_one, name: IIIFPlug.Supervisor]

    Logger.info("Starting application...")
    Supervisor.start_link(children, opts)
  end
end
