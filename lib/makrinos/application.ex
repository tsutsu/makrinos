defmodule Makrinos.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Makrinos.Registry}
    ]

    opts = [strategy: :one_for_one, name: Makrinos.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
