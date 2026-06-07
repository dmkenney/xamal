defmodule Xamal.TTYTest do
  use ExUnit.Case, async: true

  alias Xamal.TTY

  describe "unwrap_message/2" do
    test "unwraps OTP raw reader events" do
      tty = %TTY{backend: {:otp_raw, self()}}

      assert TTY.unwrap_message(tty, {{:xamal_tty, :reader}, self(), {:data, "a"}}) ==
               {:data, "a"}

      assert TTY.unwrap_message(tty, {{:xamal_tty, :reader}, self(), :eof}) == :eof
    end

    test "ignores unrelated messages" do
      tty = %TTY{backend: {:otp_raw, self()}}

      assert TTY.unwrap_message(tty, {:ssh_cm, :conn, {:closed, :channel}}) == :unknown
      assert TTY.port(tty) == nil
    end
  end

  test "rejects unknown backends before touching the terminal" do
    assert {:error, message} = TTY.start_link(backend: :missing)
    assert message =~ "invalid TTY backend"
  end
end
