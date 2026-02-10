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
  test "multiple command substitutions run in parallel", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")

    # Each sleep 0.2s — sequential would take 0.6s+, parallel should be ~0.2s
    File.write!(secrets_path, """
    A=$(sleep 0.2 && echo aaa)
    B=$(sleep 0.2 && echo bbb)
    C=$(sleep 0.2 && echo ccc)
    """)

    t0 = System.monotonic_time(:millisecond)
    secrets = Secrets.new(secrets_path: secrets_path)
    elapsed = System.monotonic_time(:millisecond) - t0

    assert Secrets.fetch(secrets, "A") == "aaa"
    assert Secrets.fetch(secrets, "B") == "bbb"
    assert Secrets.fetch(secrets, "C") == "ccc"
    # Parallel: should complete well under 500ms (sequential would be 600ms+)
    assert elapsed < 500
  end

  @tag :tmp_dir
  test "mix of plain and command-substituted values", %{tmp_dir: dir} do
    secrets_path = Path.join(dir, "secrets")

    File.write!(secrets_path, """
    PLAIN=hello
    DYNAMIC=$(echo world)
    ALSO_PLAIN=foo
    """)

    secrets = Secrets.new(secrets_path: secrets_path)
    assert Secrets.fetch(secrets, "PLAIN") == "hello"
    assert Secrets.fetch(secrets, "DYNAMIC") == "world"
    assert Secrets.fetch(secrets, "ALSO_PLAIN") == "foo"
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
