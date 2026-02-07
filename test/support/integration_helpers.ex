defmodule Xamal.IntegrationHelpers do
  @moduledoc false

  @deploy_yml """
  service: test-app
  servers:
    web:
      - 10.0.0.1
      - 10.0.0.2
    worker:
      hosts:
        - 10.0.0.3
      cmd: bin/test_app eval "Worker.start()"
  ssh:
    user: deploy
    port: 22
    connect_timeout: 0
  caddy:
    host: test.example.com
    app_port: 4000
  env:
    clear:
      PHX_HOST: test.example.com
    secret:
      - SECRET_KEY_BASE
  release:
    name: test_app
    mix_env: prod
  health_check:
    path: /health
    interval: 1
    timeout: 30
  boot:
    limit: 2
    wait: 1
  retain_releases: 3
  aliases:
    info: config
  """

  @secrets_file """
  SECRET_KEY_BASE=super_secret_value_123
  """

  def setup_temp_dir do
    dir = Path.join(System.tmp_dir!(), "xamal_e2e_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  def setup_config(dir) do
    File.mkdir_p!(Path.join(dir, "config"))
    File.write!(Path.join(dir, "config/deploy.yml"), @deploy_yml)
    File.mkdir_p!(Path.join(dir, ".xamal"))
    File.write!(Path.join(dir, ".xamal/secrets"), @secrets_file)
  end

  def setup_git_repo(dir) do
    System.cmd(
      "sh",
      [
        "-c",
        "git init -b master --quiet 2>/dev/null && " <>
          "git config user.email test@test.com && " <>
          "git config user.name Test && " <>
          "git add . && " <>
          "git commit -m init --quiet 2>/dev/null"
      ],
      cd: dir
    )
  end

  def xamal(args, dir) do
    System.cmd("timeout", ["2", Path.expand("xamal")] ++ args, cd: dir, stderr_to_stdout: true)
  end

  def deploy_yml, do: @deploy_yml
  def secrets_file, do: @secrets_file
end
