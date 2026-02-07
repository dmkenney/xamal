defmodule Xamal.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Xamal.SSH.ConnectionPool,
      Xamal.Commander
    ]

    opts = [strategy: :one_for_one, name: Xamal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
