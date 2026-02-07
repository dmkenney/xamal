defmodule Xamal.Configuration.Servers do
  @moduledoc """
  Parses the servers section of config.

  Supports both array format (implicit "web" role) and map format
  (named roles).
  """

  defstruct [:roles]

  @doc """
  Parse the servers config into role names and their configurations.

  Returns a struct with roles as a list of {name, config} tuples.
  """
  def new(nil) do
    %__MODULE__{roles: []}
  end

  def new(servers) when is_list(servers) do
    # Simple array of hosts → single "web" role
    %__MODULE__{roles: [{"web", servers}]}
  end

  def new(servers) when is_map(servers) do
    roles = Enum.sort_by(servers, fn {name, _} -> name end)

    %__MODULE__{roles: roles}
  end

  def role_names(%__MODULE__{roles: roles}) do
    Enum.map(roles, fn {name, _} -> name end)
  end
end
