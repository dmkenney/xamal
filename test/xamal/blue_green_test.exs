defmodule Xamal.BlueGreenTest do
  use ExUnit.Case, async: true

  alias Xamal.BlueGreen

  @config %Xamal.Configuration{
    raw_config: %{"service" => "my-app"},
    caddy: %Xamal.Configuration.Caddy{app_port: 4000},
    ssh: %Xamal.Configuration.Ssh{user: "deploy"},
    release: %Xamal.Configuration.Release{name: "webapp", mix_env: "prod"}
  }

  describe "renamed_release_message/3" do
    test "names the old release and gives the cleanup for both ports" do
      message =
        BlueGreen.renamed_release_message(
          "10.0.0.5",
          @config,
          "/etc/systemd/system/myapp@.service\n"
        )

      assert message =~ "different release name (myapp)"
      assert message =~ ~s(release.name is now "webapp")
      assert message =~ "sudo systemctl disable --now myapp@4000 myapp@4001"
      assert message =~ "sudo rm /etc/systemd/system/myapp@.service"
      assert message =~ "sudo systemctl daemon-reload"
      assert message =~ "mix xamal.server.bootstrap && mix xamal.deploy"
    end

    test "lists every old name when there are several" do
      found = "/etc/systemd/system/old_one@.service\n/etc/systemd/system/old_two@.service\n"
      message = BlueGreen.renamed_release_message("h", @config, found)

      assert message =~ "(old_one, old_two)"
      assert message =~ "sudo rm /etc/systemd/system/old_one@.service"
      assert message =~ "sudo rm /etc/systemd/system/old_two@.service"
    end
  end
end
