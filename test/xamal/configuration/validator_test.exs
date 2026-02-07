defmodule Xamal.Configuration.ValidatorTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration

  @valid_config %{
    "service" => "my-app",
    "servers" => %{"web" => ["10.0.0.1"]}
  }

  describe "validate!/1" do
    test "accepts valid config" do
      config = Configuration.new(@valid_config)
      assert %Configuration{} = config
    end

    test "rejects service with spaces" do
      assert_raise ArgumentError, ~r/Service name/, fn ->
        Configuration.new(Map.put(@valid_config, "service", "my app"))
      end
    end

    test "rejects service with special characters" do
      assert_raise ArgumentError, ~r/Service name/, fn ->
        Configuration.new(Map.put(@valid_config, "service", "my@app!"))
      end
    end

    test "accepts service with hyphens and underscores" do
      config = Configuration.new(Map.put(@valid_config, "service", "my-cool_app"))
      assert Configuration.service(config) == "my-cool_app"
    end

    test "rejects nil servers" do
      assert_raise ArgumentError, ~r/No servers/, fn ->
        Configuration.new(Map.put(@valid_config, "servers", nil))
      end
    end

    test "rejects retain_releases of 0" do
      assert_raise ArgumentError, ~r/Must retain/, fn ->
        Configuration.new(Map.put(@valid_config, "retain_releases", 0))
      end
    end

    test "rejects negative retain_releases" do
      assert_raise ArgumentError, ~r/Must retain/, fn ->
        Configuration.new(Map.put(@valid_config, "retain_releases", -1))
      end
    end

    test "accepts require_destination without destination" do
      assert_raise ArgumentError, ~r/must specify a destination/, fn ->
        config = Map.put(@valid_config, "require_destination", true)
        Configuration.new(config)
      end
    end
  end
end
