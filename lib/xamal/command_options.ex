defmodule Xamal.CommandOptions do
  @moduledoc false

  alias Xamal.{Configuration, Context}

  def build_context(config, opts) do
    config
    |> Context.new()
    |> put_host_filter(opts)
    |> put_role_filter(opts)
    |> put_primary_filter(opts)
    |> put_verbosity(opts)
  end

  def configure_logger(opts) do
    cond do
      Keyword.get(opts, :verbose) -> Logger.configure(level: :debug)
      Keyword.get(opts, :quiet) -> Logger.configure(level: :error)
      true -> :ok
    end
  end

  defp put_host_filter(context, opts) do
    if hosts = Keyword.get(opts, :hosts) do
      Context.put_specific_hosts(context, String.split(hosts, ","))
    else
      context
    end
  end

  defp put_role_filter(context, opts) do
    if roles = Keyword.get(opts, :roles) do
      Context.put_specific_roles(context, String.split(roles, ","))
    else
      context
    end
  end

  defp put_primary_filter(context, opts) do
    if Keyword.get(opts, :primary) do
      case Configuration.primary_host(context.config) do
        nil -> context
        primary -> Context.put_specific_hosts(context, [primary])
      end
    else
      context
    end
  end

  defp put_verbosity(context, opts) do
    cond do
      Keyword.get(opts, :verbose) -> Context.put_verbosity(context, :debug)
      Keyword.get(opts, :quiet) -> Context.put_verbosity(context, :error)
      true -> context
    end
  end
end
