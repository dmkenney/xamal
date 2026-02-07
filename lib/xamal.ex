defmodule Xamal do
  @moduledoc """
  Xamal deploys Elixir releases to bare metal servers via SSH.

  An Elixir rewrite of Kamal that replaces Docker with Elixir releases
  and kamal-proxy with Caddy for reverse proxy and TLS.
  """

  @version Mix.Project.config()[:version]

  def version, do: @version
end
