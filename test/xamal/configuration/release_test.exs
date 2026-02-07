defmodule Xamal.Configuration.ReleaseTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Release

  describe "new/2" do
    test "parses release config" do
      release =
        Release.new(%{"name" => "my_app", "mix_env" => "staging"}, %{"service" => "my-app"})

      assert release.name == "my_app"
      assert release.mix_env == "staging"
    end

    test "defaults name from service" do
      release = Release.new(%{}, %{"service" => "my-cool-app"})

      assert release.name == "my_cool_app"
      assert release.mix_env == "prod"
    end

    test "bin_path returns path" do
      release = Release.new(%{"name" => "my_app"}, %{"service" => "my-app"})

      assert Release.bin_path(release) == "bin/my_app"
    end
  end
end
