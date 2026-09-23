defmodule Xamal.Configuration.SshTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Ssh

  describe "new/1" do
    test "parses all SSH options" do
      config = %{
        "user" => "deploy",
        "port" => 2222,
        "proxy" => "bastion.example.com",
        "keys" => ["~/.ssh/id_ed25519"],
        "max_concurrent_starts" => 10
      }

      ssh = Ssh.new(config)
      assert ssh.user == "deploy"
      assert ssh.port == 2222
      assert ssh.proxy == "bastion.example.com"
      assert ssh.keys == ["~/.ssh/id_ed25519"]
      assert ssh.max_concurrent_starts == 10
    end

    test "defaults" do
      ssh = Ssh.new(%{})
      assert ssh.user == "root"
      assert ssh.port == 22
      assert ssh.proxy == nil
      assert ssh.log_level == :error
      assert ssh.max_concurrent_starts == 30
      assert ssh.pool_idle_timeout == 900
      assert ssh.dns_retries == 3
    end

    test "handles nil config" do
      ssh = Ssh.new(nil)
      assert ssh.user == "root"
      assert ssh.port == 22
    end

    test "parses log levels" do
      assert Ssh.new(%{"log_level" => "debug"}).log_level == :debug
      assert Ssh.new(%{"log_level" => "info"}).log_level == :info
      assert Ssh.new(%{"log_level" => "warn"}).log_level == :warning
      assert Ssh.new(%{"log_level" => "error"}).log_level == :error
    end
  end

  describe "connect_options/1" do
    test "includes basic options" do
      ssh = Ssh.new(%{"user" => "deploy"})
      opts = Ssh.connect_options(ssh)

      assert Keyword.get(opts, :user) == ~c"deploy"
      assert Keyword.get(opts, :silently_accept_hosts) == true
      assert Keyword.get(opts, :user_interaction) == false
    end

    test "loads the configured key file itself, whatever its name" do
      path = Path.join(System.tmp_dir!(), "deploy_key_#{System.unique_integer([:positive])}")
      File.write!(path, "key contents")
      on_exit(fn -> File.rm(path) end)

      opts = Ssh.connect_options(Ssh.new(%{"keys" => [path]}))

      assert Keyword.get(opts, :key_cb) ==
               {Xamal.SSH.KeyProvider, key_data: "key contents"}

      refute Keyword.has_key?(opts, :user_dir)
    end

    test "uses :ssh defaults when no configured key exists on disk" do
      opts = Ssh.connect_options(Ssh.new(%{"keys" => ["/nonexistent/xamal/key"]}))

      refute Keyword.has_key?(opts, :key_cb)
      refute Keyword.has_key?(opts, :user_dir)
    end

    test "passes a jump host through for Xamal.SSH.Proxy" do
      opts = Ssh.connect_options(Ssh.new(%{"proxy" => "admin@bastion:2222"}))

      assert Keyword.get(opts, :xamal_proxy) == "admin@bastion:2222"
    end

    test "passes a proxy command through for Xamal.SSH.Proxy" do
      opts = Ssh.connect_options(Ssh.new(%{"proxy_command" => "nc %h %p"}))

      assert Keyword.get(opts, :xamal_proxy_command) == "nc %h %p"
    end
  end
end
