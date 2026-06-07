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

  # Globals that take a value, so the splitter knows to consume the next token.
  @global_value_switches for {name, :string} <- @global_switches, do: name

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

  @doc """
  Splits raw task args into recognized global switches and the rest.

  Scans leading tokens for known global switches, forwarding any unrecognized
  *flag* to the task verbatim, so per-task flags like `-f`/`--follow`/`-n`/
  `--since` work even when they lead (Mix tasks have no subcommand token to
  anchor `parse_head` against). Scanning stops at the first positional argument
  (a bare word) or a `--` terminator; everything from there on is passed through
  untouched. This mirrors the pre-migration escript, where globals could appear
  before or right after the command but never inside its argv — so a remote
  command like `app.exec df -h /` keeps its own flags instead of having `-h`
  stolen as `--hosts`.

  Returns `{global_opts, task_args}`. Public for testing; not part of the API.
  """
  @spec parse_global_options(list(String.t())) :: {keyword(), list(String.t())}
  def parse_global_options(args) do
    {global_args, rest} = partition_global_options(args, [])

    {opts, _, _} =
      OptionParser.parse(global_args, strict: @global_switches, aliases: @global_aliases)

    {opts, rest}
  end

  # `--` terminator and anything after it belong to the task, verbatim.
  defp partition_global_options(["--" | _] = rest, globals) do
    {Enum.reverse(globals), rest}
  end

  defp partition_global_options([], globals) do
    {Enum.reverse(globals), []}
  end

  defp partition_global_options([token | rest] = args, globals) do
    case classify_option(token) do
      {:global, name, :flag} when name in @global_value_switches ->
        # A value-taking global (given without `=`) consumes the next token.
        case rest do
          [value | rest2] -> partition_global_options(rest2, [value, token | globals])
          [] -> partition_global_options([], [token | globals])
        end

      {:global, _name, _kind} ->
        partition_global_options(rest, [token | globals])

      :flag ->
        # Unrecognized flag (a task flag): forward it but keep scanning, since a
        # global may still follow it before the first positional.
        {trailing_globals, leftover} = partition_global_options(rest, [])
        {Enum.reverse(globals, trailing_globals), [token | leftover]}

      :positional ->
        # First bare word: the task owns this and everything after it.
        {Enum.reverse(globals), args}
    end
  end

  # Identify whether a token names a recognized global switch, and whether it
  # already carries an inline value (`--flag=value` or clustered short form).
  defp classify_option("--" <> _ = token) do
    {flag, inline?} =
      case String.split(token, "=", parts: 2) do
        [flag] -> {flag, false}
        [flag, _value] -> {flag, true}
      end

    name = flag |> String.trim_leading("-") |> String.replace("-", "_") |> existing_atom()

    if name && Keyword.has_key?(@global_switches, name) do
      {:global, name, option_kind(inline?)}
    else
      :flag
    end
  end

  defp classify_option("-" <> rest) when rest != "" do
    alias_atom = rest |> String.first() |> existing_atom()

    case alias_atom && Keyword.get(@global_aliases, alias_atom) do
      nil -> :flag
      name -> {:global, name, option_kind(String.length(rest) > 1)}
    end
  end

  defp classify_option(_token), do: :positional

  defp option_kind(true), do: :inline
  defp option_kind(false), do: :flag

  defp existing_atom(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> nil
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
