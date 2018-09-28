defmodule MakrinosTest do
  use ExUnit.Case

  doctest Makrinos.MessageFormat

  doctest Makrinos.HTTPClient
  doctest Makrinos.HTTPAdapter

  doctest Makrinos.UDSClient
  doctest Makrinos.UDSAdapter
end
