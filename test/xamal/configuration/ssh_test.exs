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

    test "includes user_dir when keys specified" do
      ssh = Ssh.new(%{"keys" => ["~/.ssh/id_ed25519"]})
      opts = Ssh.connect_options(ssh)

      assert Keyword.has_key?(opts, :user_dir)
    end
  end
end
