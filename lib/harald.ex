defmodule Harald do
  @moduledoc """
  Elixir library for working directly with Bluetooth via the HCI.
  """

  def get_system_status(namespace) do
    Harald.Transport.send_command(namespace, <<1, 0xFE1F::little-size(16), 0>>)
  end

  def read_bd_addr(namespace) do
    Harald.Transport.send_command(namespace, <<1, 9, 16, 0>>)
  end
end
