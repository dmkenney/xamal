defmodule Xamal.Configuration.BuilderTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Builder

  describe "new/1" do
    test "defaults to local" do
      builder = Builder.new(%{})

      assert builder.local == true
      assert builder.docker == false
      assert builder.remote == nil
    end

    test "docker mode with true" do
      builder = Builder.new(%{"docker" => true, "local" => false})

      assert builder.local == false
      assert builder.docker == true
    end

    test "docker mode with custom image" do
      builder = Builder.new(%{"docker" => "my-org/elixir:1.18", "local" => false})

      assert builder.local == false
      assert builder.docker == "my-org/elixir:1.18"
    end

    test "remote mode" do
      builder = Builder.new(%{"remote" => "build@build-server"})

      assert builder.remote == "build@build-server"
    end

    test "args" do
      builder = Builder.new(%{"args" => %{"ELIXIR_VERSION" => "1.18.3"}})

      assert builder.args == %{"ELIXIR_VERSION" => "1.18.3"}
    end
  end

  describe "predicates" do
    test "local?/1" do
      assert Builder.local?(Builder.new(%{}))
      refute Builder.local?(Builder.new(%{"local" => false}))
    end

    test "docker?/1" do
      refute Builder.docker?(Builder.new(%{}))
      assert Builder.docker?(Builder.new(%{"docker" => true}))
      assert Builder.docker?(Builder.new(%{"docker" => "my-image:latest"}))
      refute Builder.docker?(Builder.new(%{"docker" => false}))
      refute Builder.docker?(Builder.new(%{"docker" => nil}))
    end

    test "remote?/1" do
      refute Builder.remote?(Builder.new(%{}))
      assert Builder.remote?(Builder.new(%{"remote" => "build@server"}))
    end
  end

  describe "docker_image/1" do
    test "returns custom image when docker is a string" do
      builder = Builder.new(%{"docker" => "my-org/elixir:1.18"})
      assert Builder.docker_image(builder) == "my-org/elixir:1.18"
    end

    test "returns default image when docker is true" do
      builder = Builder.new(%{"docker" => true})
      assert Builder.docker_image(builder) =~ "hexpm/elixir"
    end

    test "returns default image when docker is false" do
      builder = Builder.new(%{})
      assert Builder.docker_image(builder) =~ "hexpm/elixir"
    end
  end
end
