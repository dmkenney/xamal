defmodule Xamal.SSH.KeyProviderTest do
  use ExUnit.Case, async: true

  alias Xamal.SSH.KeyProvider

  @moduletag :tmp_dir

  # ssh-keygen writes the OpenSSH format ("BEGIN OPENSSH PRIVATE KEY") by
  # default, which :public_key alone can't read.
  defp generate_key(dir, type) do
    path = Path.join(dir, "key_#{type}")
    {_, 0} = System.cmd("ssh-keygen", ["-q", "-t", type, "-N", "", "-f", path])
    File.read!(path)
  end

  test "reads an OpenSSH-format ed25519 key", %{tmp_dir: dir} do
    key_data = generate_key(dir, "ed25519")
    assert key_data =~ "BEGIN OPENSSH PRIVATE KEY"

    assert {:ok, _key} =
             KeyProvider.user_key(:"ssh-ed25519", key_cb_private: [key_data: key_data])
  end

  test "reads an OpenSSH-format RSA key", %{tmp_dir: dir} do
    key_data = generate_key(dir, "rsa")

    assert {:ok, _key} =
             KeyProvider.user_key(:"rsa-sha2-256", key_cb_private: [key_data: key_data])
  end

  test "reports no key for a different algorithm", %{tmp_dir: dir} do
    key_data = generate_key(dir, "ed25519")

    assert KeyProvider.user_key(:"ssh-rsa", key_cb_private: [key_data: key_data]) ==
             {:error, :no_matching_key}
  end

  test "reports no key for unreadable data" do
    assert KeyProvider.user_key(:"ssh-ed25519", key_cb_private: [key_data: "not a key"]) ==
             {:error, :no_matching_key}
  end
end
