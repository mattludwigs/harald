defmodule Harald.HCITest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Harald.HCI

  doctest Harald.HCI, import: true
end
