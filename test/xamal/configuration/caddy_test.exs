defmodule Xamal.Configuration.CaddyTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Caddy

  describe "new/1" do
    test "parses caddy config" do
      caddy = Caddy.new(%{"host" => "app.example.com", "app_port" => 8080})

      assert caddy.host == "app.example.com"
      assert caddy.app_port == 8080
    end

    test "defaults" do
      caddy = Caddy.new(%{})

      assert caddy.host == nil
      assert caddy.hosts == []
      assert caddy.app_port == 4000
      assert caddy.ssl == true
    end

    test "ssl option" do
      caddy = Caddy.new(%{"ssl" => false})
      assert caddy.ssl == false
    end

    test "handles nil" do
      caddy = Caddy.new(nil)
      assert caddy.app_port == 4000
    end
  end

  describe "hostnames/1" do
    test "single host" do
      caddy = Caddy.new(%{"host" => "app.example.com"})
      assert Caddy.hostnames(caddy) == ["app.example.com"]
    end

    test "multiple hosts" do
      caddy = Caddy.new(%{"host" => "app.example.com", "hosts" => ["www.example.com"]})
      assert Caddy.hostnames(caddy) == ["app.example.com", "www.example.com"]
    end

    test "hosts only" do
      caddy = Caddy.new(%{"hosts" => ["a.example.com", "b.example.com"]})
      assert Caddy.hostnames(caddy) == ["a.example.com", "b.example.com"]
    end

    test "no hosts" do
      caddy = Caddy.new(%{})
      assert Caddy.hostnames(caddy) == []
    end
  end

  describe "alt_port/1" do
    test "returns app_port + 1" do
      caddy = Caddy.new(%{"app_port" => 4000})
      assert Caddy.alt_port(caddy) == 4001
    end
  end

  describe "generate_caddyfile/2" do
    test "with host" do
      caddy = Caddy.new(%{"host" => "app.example.com"})
      caddyfile = Caddy.generate_caddyfile(caddy, 4000)

      assert caddyfile =~ "app.example.com"
      assert caddyfile =~ "reverse_proxy localhost:4000"
    end

    test "without host uses port 80" do
      caddy = Caddy.new(%{})
      caddyfile = Caddy.generate_caddyfile(caddy, 4000)

      assert Regex.match?(~r/:80/, caddyfile)
      assert caddyfile =~ "reverse_proxy localhost:4000"
    end

    test "ssl false prefixes hosts with http://" do
      caddy = Caddy.new(%{"host" => "app.example.com", "ssl" => false})
      caddyfile = Caddy.generate_caddyfile(caddy, 4000)

      assert caddyfile =~ "http://app.example.com"
      assert caddyfile =~ "reverse_proxy localhost:4000"
    end

    test "ssl false with multiple hosts" do
      caddy =
        Caddy.new(%{"host" => "app.example.com", "hosts" => ["www.example.com"], "ssl" => false})

      caddyfile = Caddy.generate_caddyfile(caddy, 4000)

      assert caddyfile =~ "http://app.example.com, http://www.example.com"
    end

    test "ssl false without hosts still uses port 80" do
      caddy = Caddy.new(%{"ssl" => false})
      caddyfile = Caddy.generate_caddyfile(caddy, 4000)

      assert caddyfile =~ ":80"
    end
  end

  describe "maintenance_caddyfile/1" do
    test "generates maintenance response" do
      caddy = Caddy.new(%{"host" => "app.example.com"})
      caddyfile = Caddy.maintenance_caddyfile(caddy)

      assert caddyfile =~ "app.example.com"
      assert caddyfile =~ "503"
      assert caddyfile =~ "maintenance"
    end
  end
end
