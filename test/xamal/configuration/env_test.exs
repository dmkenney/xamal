defmodule Xamal.Configuration.EnvTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Env

  describe "new/2" do
    test "parses clear/secret format" do
      config = %{
        "clear" => %{"PHX_HOST" => "example.com", "MIX_ENV" => "prod"},
        "secret" => ["SECRET_KEY_BASE", "DATABASE_URL"]
      }

      env = Env.new(config, nil)
      assert env.clear == %{"PHX_HOST" => "example.com", "MIX_ENV" => "prod"}
      assert env.secret_keys == ["SECRET_KEY_BASE", "DATABASE_URL"]
    end

    test "strips reserved vars and warns" do
      config = %{
        "clear" => %{"PHX_HOST" => "example.com", "PORT" => 4000}
      }

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          env = Env.new(config, nil)
          assert env.clear == %{"PHX_HOST" => "example.com"}
          send(self(), {:env, env})
        end)

      assert stderr =~ "PORT in env.clear is ignored"
    end

    test "parses plain key-value format" do
      config = %{"PHX_HOST" => "example.com", "POOL_SIZE" => 10}

      env = Env.new(config, nil)
      assert env.clear == %{"PHX_HOST" => "example.com", "POOL_SIZE" => "10"}
      assert env.secret_keys == []
    end

    test "handles empty config" do
      env = Env.new(%{}, nil)
      assert env.clear == %{}
      assert env.secret_keys == []
    end

    test "handles nil config" do
      env = Env.new(nil, nil)
      assert env.clear == %{}
      assert env.secret_keys == []
    end
  end

  describe "merge/2" do
    test "merges clear vars and unions secret keys" do
      base = %Env{clear: %{"A" => "1", "B" => "2"}, secret_keys: ["SECRET_A"], secrets: nil}
      override = %Env{clear: %{"B" => "3", "C" => "4"}, secret_keys: ["SECRET_B"], secrets: nil}

      merged = Env.merge(base, override)
      assert merged.clear == %{"A" => "1", "B" => "3", "C" => "4"}
      assert merged.secret_keys == ["SECRET_A", "SECRET_B"]
    end

    test "deduplicates secret keys" do
      base = %Env{clear: %{}, secret_keys: ["SECRET_A", "SECRET_B"], secrets: nil}
      override = %Env{clear: %{}, secret_keys: ["SECRET_B", "SECRET_C"], secrets: nil}

      merged = Env.merge(base, override)
      assert merged.secret_keys == ["SECRET_A", "SECRET_B", "SECRET_C"]
    end
  end

  describe "clear_map/1" do
    test "returns clear env vars" do
      env = %Env{clear: %{"A" => "1"}, secret_keys: [], secrets: nil}
      assert Env.clear_map(env) == %{"A" => "1"}
    end
  end
end
