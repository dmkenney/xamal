defmodule Xamal.SSH.KeyProvider do
  @moduledoc """
  Custom SSH key callback that serves key data from memory.

  Used when `key_data` is set in SSH config, allowing keys to be
  provided without writing them to disk (e.g. fetched from 1Password via `op read`).
  """

  @behaviour :ssh_client_key_api

  @impl true
  def is_host_key(_key, _host, _algorithm, _opts) do
    true
  end

  @impl true
  def add_host_key(_host, _key, _opts) do
    :ok
  end

  @impl true
  def user_key(algorithm, opts) do
    key_data = opts[:key_cb_private][:key_data]

    case decode_pem_key(key_data, algorithm) do
      {:ok, key} -> {:ok, key}
      :none -> {:error, :no_matching_key}
    end
  end

  defp decode_pem_key(pem_data, algorithm) when is_binary(pem_data) do
    pem_data
    |> :public_key.pem_decode()
    |> Enum.find_value(:none, fn entry ->
      key = :public_key.pem_entry_decode(entry)
      if key_matches_algorithm?(key, algorithm), do: {:ok, key}
    end)
  end

  defp decode_pem_key(_, _), do: :none

  # PKCS#8 Ed25519 (OID 1.3.101.112)
  defp key_matches_algorithm?(
         {:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 112}}, _, _},
         :"ssh-ed25519"
       ),
       do: true

  # ECDSA keys (5-element tuple)
  defp key_matches_algorithm?({:ECPrivateKey, _, _, _, _}, alg),
    do: String.starts_with?(Atom.to_string(alg), "ecdsa-sha2-")

  # ECDSA keys (6-element tuple, non-Ed25519 curves)
  defp key_matches_algorithm?({:ECPrivateKey, _, _, curve, _, _}, alg)
       when curve != {:namedCurve, {1, 3, 101, 112}},
       do: String.starts_with?(Atom.to_string(alg), "ecdsa-sha2-")

  defp key_matches_algorithm?({:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _}, alg)
       when alg in [:"ssh-rsa", :"rsa-sha2-256", :"rsa-sha2-512"],
       do: true

  defp key_matches_algorithm?({:ed_pri, :ed25519, _, _}, :"ssh-ed25519"), do: true

  defp key_matches_algorithm?(_, _), do: false
end
