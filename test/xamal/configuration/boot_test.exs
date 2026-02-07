defmodule Xamal.Configuration.BootTest do
  use ExUnit.Case, async: true

  alias Xamal.Configuration.Boot

  describe "new/1" do
    test "parses boot config" do
      boot = Boot.new(%{"limit" => 10, "wait" => 2, "parallel_roles" => true})

      assert boot.limit == 10
      assert boot.wait == 2
      assert boot.parallel_roles == true
    end

    test "defaults" do
      boot = Boot.new(%{})

      assert boot.limit == nil
      assert boot.wait == nil
      assert boot.parallel_roles == false
    end

    test "handles nil config" do
      boot = Boot.new(nil)
      assert boot.limit == nil
    end

    test "parses percentage limit" do
      boot = Boot.new(%{"limit" => "50%"})
      assert boot.limit == {:percent, 50}
    end

    test "parses string integer limit" do
      boot = Boot.new(%{"limit" => "5"})
      assert boot.limit == 5
    end
  end

  describe "resolved_limit/2" do
    test "nil limit returns nil" do
      boot = Boot.new(%{})
      assert Boot.resolved_limit(boot, 100) == nil
    end

    test "integer limit returns as-is" do
      boot = Boot.new(%{"limit" => 5})
      assert Boot.resolved_limit(boot, 100) == 5
    end

    test "percentage limit calculates from host count" do
      boot = Boot.new(%{"limit" => "25%"})
      assert Boot.resolved_limit(boot, 20) == 5
    end

    test "percentage limit minimum 1" do
      boot = Boot.new(%{"limit" => "1%"})
      assert Boot.resolved_limit(boot, 3) == 1
    end

    test "percentage limit rounds down" do
      boot = Boot.new(%{"limit" => "33%"})
      assert Boot.resolved_limit(boot, 10) == 3
    end
  end
end
