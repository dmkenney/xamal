defmodule Xamal.SSH.ProxyTest do
  use ExUnit.Case, async: true

  alias Xamal.SSH.Proxy

  describe "parse_proxy/2" do
    test "reads user, host, and port" do
      assert Proxy.parse_proxy("admin@bastion.example.com:2222", user: ~c"deploy") ==
               {"admin", "bastion.example.com", 2222}
    end

    test "defaults the user to the connection's user and the port to 22" do
      assert Proxy.parse_proxy("bastion", user: ~c"deploy") == {"deploy", "bastion", 22}
    end
  end

  describe "expand_command/4" do
    test "substitutes host, port, and user like OpenSSH" do
      assert Proxy.expand_command("ssh -W %h:%p %r@bastion", "10.0.0.5", 22, "deploy") ==
               "ssh -W 10.0.0.5:22 deploy@bastion"
    end

    test "turns %% into a literal %" do
      assert Proxy.expand_command("echo 100%%", "h", 22, "u") == "echo 100%"
    end
  end
end
