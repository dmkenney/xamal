# Tests tagged :systemd parse env files with the real systemd. They run only
# where a user systemd manager is available (not in CI containers).
systemd? =
  System.find_executable("systemd-run") != nil and
    match?(
      {_, 0},
      System.cmd("systemd-run", ["--user", "--quiet", "--pipe", "--wait", "true"],
        stderr_to_stdout: true
      )
    )

ExUnit.start(exclude: if(systemd?, do: [], else: [:systemd]))
