defmodule DevServer do
  use Application

  require Logger

  @moduledoc false

  def start(_type, _args) do
    children = [
      {Bandit, plug: DevServerRouter}
    ]

    opts = [strategy: :one_for_one, name: DevServer.Supervisor]

    Logger.info("Starting dev server...")
    Supervisor.start_link(children, opts)
  end
end
