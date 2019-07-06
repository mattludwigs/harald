defmodule Harald.Generators.HCI do
  @moduledoc """
  StreamData generators for HCI.
  """

  use ExUnitProperties
  require Harald.Spec, as: Spec

  def generate(:null_terminated, opts) when is_list(opts) do
    length = Keyword.get_lazy(opts, :length, fn -> Enum.random(1..255) end)

    :ascii
    |> StreamData.string()
    |> StreamData.map(fn x ->
      case length - byte_size(x) do
        0 -> x
        space when space < 0 -> String.slice(x, 0..(length - 1))
        space -> x <> <<0>> <> Enum.at(StreamData.binary(length: space - 1), 0)
      end
    end)
  end

  # Spec.define_generators()
end
