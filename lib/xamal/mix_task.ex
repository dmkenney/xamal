defmodule Xamal.MixTask do
  @moduledoc false

  alias Xamal.{CommandOptions, Configuration}

  defmacro __using__(opts) do
    callback = Keyword.fetch!(opts, :run)

    quote bind_quoted: [callback: callback] do
      use Mix.Task

      @xamal_callback callback

      @impl true
      def run(args) do
        Xamal.MixTask.run(args, @xamal_callback)
      end
    end
  end

  @global_switches [
    verbose: :boolean,
    quiet: :boolean,
    version: :string,
    primary: :boolean,
    hosts: :string,
    roles: :string,
    config_file: :string,
    destination: :string,
    skip_hooks: :boolean,
    skip_dirty_check: :boolean,
    skip_push: :boolean,
    confirmed: :boolean
  ]

  @global_aliases [
    v: :verbose,
    q: :quiet,
    p: :primary,
    h: :hosts,
    r: :roles,
    c: :config_file,
    d: :destination,
    H: :skip_hooks,
    y: :confirmed
  ]

  @type callback ::
          {module(), atom()} | (list(String.t()), keyword(), Xamal.Context.t() -> term())

  @spec run(list(String.t()), callback()) :: term()
  def run(args, {module, function}) when is_atom(module) and is_atom(function) do
    run(args, fn args, opts, context -> invoke(module, function, args, opts, context) end)
  end

  def run(args, callback) when is_function(callback) do
    Application.ensure_all_started(:xamal)

    {opts, rest} = parse_global_options(args)
    context = opts |> load_config!() |> build_context(opts)
    dispatch(callback, rest, opts, context)
  end

  defp parse_global_options(args) do
    {opts, rest, invalid} =
      OptionParser.parse_head(args, strict: @global_switches, aliases: @global_aliases)

    if invalid != [] do
      invalid_options = Enum.map_join(invalid, ", ", fn {flag, _value} -> flag end)
      Mix.raise("Unknown option: #{invalid_options}")
    end

    {opts, rest}
  end

  defp load_config!(opts) do
    config_file = Keyword.get(opts, :config_file, "config/xamal.exs")

    unless File.exists?(config_file) do
      Mix.raise("Configuration file not found: #{config_file}. Run 'mix xamal.init'.")
    end

    Configuration.create_from(
      config_file: config_file,
      destination: Keyword.get(opts, :destination),
      version: Keyword.get(opts, :version)
    )
  end

  defp build_context(config, opts) do
    context = CommandOptions.build_context(config, opts)
    CommandOptions.configure_logger(opts)
    context
  end

  defp dispatch(callback, args, opts, context) do
    callback.(args, opts, context)
  end

  defp invoke(module, function, args, opts, context) do
    Code.ensure_loaded!(module)

    cond do
      function_exported?(module, function, 3) ->
        apply(module, function, [args, opts, context])

      function_exported?(module, function, 2) ->
        apply(module, function, [opts, context])

      true ->
        raise UndefinedFunctionError, module: module, function: function, arity: 3
    end
  end
end
