defmodule Xamal.SecretsTest do
  use ExUnit.Case, async: true

  alias Xamal.Secrets

  @tag :tmp_dir
  test "loads secrets from dotenv file", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")
    File.write!(secrets_path, "MY_SECRET=super_secret\nOTHER=value\n")

    secrets = Secrets.new(secrets_path: secrets_path)
    assert Secrets.fetch(secrets, "MY_SECRET") == "super_secret"
    assert Secrets.fetch(secrets, "OTHER") == "value"
  end

  @tag :tmp_dir
  test "loads common secrets and merges with destination", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "secrets-common"), "SHARED=common_val\n")
    File.write!(Path.join(dir, "secrets.staging"), "STAGE_KEY=stage_val\nSHARED=overridden\n")

    secrets = Secrets.new(secrets_path: Path.join(dir, "secrets"), destination: "staging")
    assert Secrets.fetch(secrets, "SHARED") == "overridden"
    assert Secrets.fetch(secrets, "STAGE_KEY") == "stage_val"
  end

  @tag :tmp_dir
  test "raises on missing secret", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")
    File.write!(secrets_path, "EXISTS=yes\n")

    secrets = Secrets.new(secrets_path: secrets_path)

    assert_raise RuntimeError, ~r/Secret 'NOPE' not found/, fn ->
      Secrets.fetch(secrets, "NOPE")
    end
  end

  @tag :tmp_dir
  test "handles quoted values", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")
    File.write!(secrets_path, ~s(DOUBLE="hello world"\nSINGLE='raw value'\n))

    secrets = Secrets.new(secrets_path: secrets_path)
    assert Secrets.fetch(secrets, "DOUBLE") == "hello world"
    assert Secrets.fetch(secrets, "SINGLE") == "raw value"
  end

  @tag :tmp_dir
  test "skips comments and blank lines", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")
    File.write!(secrets_path, "# comment\n\nKEY=val\n")

    secrets = Secrets.new(secrets_path: secrets_path)
    assert Secrets.fetch(secrets, "KEY") == "val"
    assert Secrets.to_map(secrets) == %{"KEY" => "val"}
  end

  @tag :tmp_dir
  test "command substitution with $()", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")
    File.write!(secrets_path, "DYNAMIC=$(echo hello_world)\n")

    secrets = Secrets.new(secrets_path: secrets_path)
    assert Secrets.fetch(secrets, "DYNAMIC") == "hello_world"
  end

  @tag :tmp_dir
  test "has_key? returns true/false", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")
    File.write!(secrets_path, "FOO=bar\n")

    secrets = Secrets.new(secrets_path: secrets_path)
    assert Secrets.has_key?(secrets, "FOO")
    refute Secrets.has_key?(secrets, "MISSING")
  end

  test "returns empty map when no files exist" do
    secrets = Secrets.new(secrets_path: "/tmp/nonexistent_xamal_secrets")
    assert Secrets.to_map(secrets) == %{}
  end
end
